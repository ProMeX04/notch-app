import assert from 'node:assert/strict'
import fs from 'node:fs'
import os from 'node:os'
import path from 'node:path'
import test from 'node:test'
import { checkGovernance, syncGovernance } from './agent-governance.mjs'

function fixture() {
  const root = fs.mkdtempSync(path.join(os.tmpdir(), 'notch-governance-'))
  const write = (file, content = '') => {
    const target = path.join(root, file)
    fs.mkdirSync(path.dirname(target), { recursive: true })
    fs.writeFileSync(target, content)
  }
  const requiredFiles = [
    'AGENTS.md',
    'CLAUDE.md',
    'portal/AGENTS.md',
    'portal/CLAUDE.md',
    'docs/architecture.md',
    'docs/engineering/architecture-boundaries.md',
    'docs/engineering/api-data-privacy.md',
    'docs/engineering/swift-ui-patterns.md',
    'docs/engineering/portal-ui-patterns.md',
    'docs/engineering/quality-release.md',
  ]
  for (const file of requiredFiles) {
    write(file, file === 'portal/CLAUDE.md' ? '@AGENTS.md\n' : '# Test\n')
  }
  write(
    '.agent-governance/manifest.json',
    JSON.stringify({
      skills: [
        {
          name: 'test-skill',
          displayName: 'Test Skill',
          shortDescription: 'Test generated skill',
          defaultPrompt: 'Use $test-skill.',
        },
      ],
      rules: { claude: ['architecture.md'], antigravity: ['foundation.md'] },
      requiredFiles,
    }),
  )
  write('.agent-governance/baseline.json', JSON.stringify({ mode: 'zero-debt', rules: {} }))
  write(
    '.agent-governance/skills/test-skill/SKILL.md',
    '---\nname: test-skill\ndescription: Test skill.\n---\n\n# Test\n',
  )
  write('.agent-governance/rules/claude/architecture.md', '# Claude rule\n')
  write('.agent-governance/rules/antigravity/foundation.md', '# AG rule\n')
  return { root, write }
}

test('sync creates native mirrors that pass validation', () => {
  const { root } = fixture()
  syncGovernance(root)
  assert.deepEqual(checkGovernance(root), [])
})

test('check rejects a manually changed native mirror', () => {
  const { root, write } = fixture()
  syncGovernance(root)
  write('.claude/skills/test-skill/SKILL.md', '# drifted\n')
  assert.ok(checkGovernance(root).some((error) => error.includes('edited directly')))
})

test('check rejects stale Codex skill metadata', () => {
  const { root, write } = fixture()
  syncGovernance(root)
  write('.codex/skills/test-skill/agents/openai.yaml', 'interface:\n')
  assert.ok(
    checkGovernance(root).some((error) => error.includes('Codex skill metadata')),
  )
})

test('check rejects a missing native rule target', () => {
  const { root } = fixture()
  syncGovernance(root)
  fs.rmSync(path.join(root, '.agents/rules/foundation.md'))
  assert.ok(checkGovernance(root).some((error) => error.includes('Missing generated')))
})

test('check rejects an unregistered native Notch skill', () => {
  const { root, write } = fixture()
  syncGovernance(root)
  write('.agents/skills/notch-rogue/SKILL.md', '# not canonical\n')
  assert.ok(checkGovernance(root).some((error) => error.includes('Unregistered native Notch skill')))
})

test('check rejects duplicated architecture guidance in CLAUDE.md', () => {
  const { root, write } = fixture()
  syncGovernance(root)
  write('CLAUDE.md', '@AGENTS.md\n\n## Swift Architecture Rule\n')
  assert.ok(checkGovernance(root).some((error) => error.includes('duplicates')))
})

test('check rejects a new core infrastructure dependency beyond baseline', () => {
  const { root, write } = fixture()
  syncGovernance(root)
  write('Sources/NewCore/CloudStore.swift', 'let request = URLRequest(url: endpoint)\n')
  assert.ok(
    checkGovernance(root).some((error) => error.includes('core-infrastructure')),
  )
})

test('development mode rejects baseline allowances instead of accepting debt', () => {
  const { root, write } = fixture()
  write(
    '.agent-governance/baseline.json',
    JSON.stringify({
      rules: {
        'core-infrastructure': {
          'Sources/RecordedCore/CloudStore.swift': {
            maxMatches: 1,
            reason: 'Recorded test dependency.',
          },
        },
      },
    }),
  )
  write('Sources/RecordedCore/CloudStore.swift', 'let request = URLRequest(url: endpoint)\n')
  syncGovernance(root)
  assert.ok(
    checkGovernance(root).some((error) =>
      error.includes('baseline allowances are forbidden'),
    ),
  )
})

test('baseline allowances require a documented rationale', () => {
  const { root, write } = fixture()
  write(
    '.agent-governance/baseline.json',
    JSON.stringify({
      rules: {
        'core-infrastructure': {
          'Sources/RecordedCore/CloudStore.swift': { maxMatches: 1 },
        },
      },
    }),
  )
  syncGovernance(root)
  assert.ok(
    checkGovernance(root).some((error) =>
      error.includes('Invalid governance baseline allowance'),
    ),
  )
})

test('development mode rejects runtime compatibility branches', () => {
  const { root, write } = fixture()
  syncGovernance(root)
  write(
    'Sources/AppFeature/Store.swift',
    'func load() { /* migration from previous version */ }\n',
  )
  assert.ok(
    checkGovernance(root).some((error) =>
      error.includes('development-data-compatibility'),
    ),
  )
})
