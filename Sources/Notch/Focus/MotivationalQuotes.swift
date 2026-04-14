import Foundation

struct MotivationalQuotes {
    private static let focusReminders = [
        ["English": "Deep work is a superpower.", "Tiếng Việt": "Làm việc sâu là một siêu năng lực."],
        ["English": "Focus on being productive, not busy.", "Tiếng Việt": "Hãy làm việc năng suất, đừng chỉ bận rộn."],
        ["English": "One thing at a time.", "Tiếng Việt": "Tập trung một việc duy nhất thôi nhé."],
        ["English": "Don't stop until you're proud.", "Tiếng Việt": "Đừng dừng lại cho đến khi thấy tự hào."],
        ["English": "Small steps lead to big results.", "Tiếng Việt": "Từng bước nhỏ sẽ mang lại kết quả lớn."],
        ["English": "Quality over quantity.", "Tiếng Việt": "Chất lượng hơn số lượng."],
        ["English": "Stay in the zone.", "Tiếng Việt": "Giữ vững sự tập trung nhé."],
        ["English": "Eliminate distractions.", "Tiếng Việt": "Loại bỏ mọi thứ gây xao nhãng."],
    ]

    private static let breakReminders = [
        ["English": "Stay hydrated! Drink some water.", "Tiếng Việt": "Bổ sung nước đi bạn ơi!"],
        ["English": "Relax your shoulders and breathe.", "Tiếng Việt": "Thả lỏng vai và hít thở sâu nào."],
        ["English": "Take a short walk if you can.", "Tiếng Việt": "Hãy đứng dậy đi lại một chút nhé."],
        ["English": "Rest is part of the work.", "Tiếng Việt": "Nghỉ ngơi cũng là một phần công việc."],
        ["English": "Your future self will thank you for this break.", "Tiếng Việt": "Cơ thể bạn sẽ cảm ơn vì lúc nghỉ này."],
        ["English": "Progress over perfection.", "Tiếng Việt": "Tiến bộ quan trọng hơn hoàn hảo."],
    ]

    static func getRandom(for phase: PomodoroPhase, lang: String) -> String {
        let pool = phase == .focus ? focusReminders : breakReminders
        let entry = pool.randomElement() ?? pool[0]
        return entry[lang] ?? entry["English"] ?? ""
    }
}
