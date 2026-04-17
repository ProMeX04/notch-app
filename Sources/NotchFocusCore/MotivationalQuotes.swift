import Foundation

package struct MotivationalQuote {
    package let text: String
    package let author: String
}

package struct MotivationalQuotes {
    // Format: ["en": quote, "vi": quote, "author": name]
    private static let focusReminders: [[String: String]] = [
        ["en": "The secret of getting ahead is getting started.", "vi": "Bí quyết tiến lên phía trước là bắt đầu.", "author": "Mark Twain"],
        ["en": "It's not that I'm so smart, it's just that I stay with problems longer.", "vi": "Tôi không thông minh hơn, tôi chỉ kiên nhẫn hơn với vấn đề.", "author": "Albert Einstein"],
        ["en": "The way to get started is to quit talking and begin doing.", "vi": "Cách duy nhất để bắt đầu là ngừng nói và bắt đầu làm.", "author": "Walt Disney"],
        ["en": "Concentration is the root of all the higher abilities in man.", "vi": "Sự tập trung là cội nguồn của mọi năng lực cao hơn trong con người.", "author": "Bruce Lee"],
        ["en": "The successful warrior is the average man, with laser-like focus.", "vi": "Chiến binh thành công là người bình thường với sự tập trung như tia laser.", "author": "Bruce Lee"],
        ["en": "It always seems impossible until it's done.", "vi": "Mọi thứ đều có vẻ bất khả thi cho đến khi hoàn thành.", "author": "Nelson Mandela"],
        ["en": "Do what you can, with what you have, where you are.", "vi": "Làm những gì bạn có thể, với những gì bạn có, ở nơi bạn đang đứng.", "author": "Theodore Roosevelt"],
        ["en": "Either you run the day or the day runs you.", "vi": "Hoặc bạn điều khiển ngày, hoặc ngày điều khiển bạn.", "author": "Jim Rohn"],
        ["en": "Lost time is never found again.", "vi": "Thời gian đã mất không bao giờ tìm lại được.", "author": "Benjamin Franklin"],
        ["en": "Genius is one percent inspiration and ninety-nine percent perspiration.", "vi": "Thiên tài là một phần cảm hứng và chín mươi chín phần mồ hôi.", "author": "Thomas Edison"],
        ["en": "There are no shortcuts to any place worth going.", "vi": "Không có đường tắt nào đến nơi đáng đến.", "author": "Beverly Sills"],
        ["en": "Start where you are. Use what you have. Do what you can.", "vi": "Bắt đầu từ nơi bạn đứng. Dùng những gì bạn có. Làm những gì bạn có thể.", "author": "Arthur Ashe"],
        ["en": "Action is the foundational key to all success.", "vi": "Hành động là chìa khóa nền tảng của mọi thành công.", "author": "Pablo Picasso"],
        ["en": "You don't have to be great to start, but you have to start to be great.", "vi": "Bạn không cần giỏi để bắt đầu, nhưng phải bắt đầu để trở nên giỏi.", "author": "Zig Ziglar"],
        ["en": "Schedule your priorities, don't just prioritize your schedule.", "vi": "Lên lịch cho những ưu tiên của bạn, đừng chỉ ưu tiên lịch trình.", "author": "Stephen Covey"],
        ["en": "If you spend too much time thinking about a thing, you'll never get it done.", "vi": "Nếu dành quá nhiều thời gian suy nghĩ, bạn sẽ chẳng bao giờ làm được.", "author": "Bruce Lee"],
        ["en": "Do the hard jobs first. The easy jobs will take care of themselves.", "vi": "Làm việc khó trước. Việc dễ sẽ tự lo được.", "author": "Dale Carnegie"],
        ["en": "Amateurs sit and wait for inspiration. The rest of us just get up and go to work.", "vi": "Nghiệp dư ngồi chờ cảm hứng. Người còn lại đứng dậy và làm việc.", "author": "Stephen King"],
        ["en": "You miss 100% of the shots you don't take.", "vi": "Bạn lỡ 100% cơ hội mà bạn không nắm lấy.", "author": "Wayne Gretzky"],
        ["en": "Knowing is not enough; we must apply. Willing is not enough; we must do.", "vi": "Biết thôi chưa đủ; phải áp dụng. Muốn thôi chưa đủ; phải làm.", "author": "Goethe"],
        ["en": "The expert in anything was once a beginner.", "vi": "Chuyên gia trong bất kỳ lĩnh vực nào cũng từng là người mới bắt đầu.", "author": "Helen Hayes"],
        ["en": "Simplicity is the ultimate sophistication.", "vi": "Giản đơn là đỉnh cao của tinh tế.", "author": "Leonardo da Vinci"],
        ["en": "What you do speaks so loudly that I cannot hear what you say.", "vi": "Hành động của bạn nói to đến mức tôi không nghe thấy lời bạn nói.", "author": "Ralph Waldo Emerson"],
        ["en": "Perfection is the enemy of progress.", "vi": "Sự hoàn hảo là kẻ thù của tiến bộ.", "author": "Winston Churchill"],
        ["en": "It does not matter how slowly you go as long as you do not stop.", "vi": "Đi chậm đến đâu cũng không sao, miễn là đừng dừng lại.", "author": "Khổng Tử"],
        ["en": "In the middle of every difficulty lies opportunity.", "vi": "Giữa mỗi khó khăn đều ẩn chứa một cơ hội.", "author": "Albert Einstein"],
        ["en": "He who is not courageous enough to take risks will accomplish nothing in life.", "vi": "Người không dũng cảm chấp nhận rủi ro sẽ không đạt được gì trong cuộc đời.", "author": "Muhammad Ali"],
        ["en": "Quality means doing it right when no one is looking.", "vi": "Chất lượng là làm đúng ngay cả khi không ai nhìn.", "author": "Henry Ford"],
        ["en": "Motivation gets you going, but discipline keeps you growing.", "vi": "Động lực giúp bạn bước đi, nhưng kỷ luật giúp bạn trưởng thành.", "author": "John C. Maxwell"],
        ["en": "The price of anything is the amount of life you exchange for it.", "vi": "Giá của bất cứ thứ gì chính là lượng cuộc sống bạn đổi lấy nó.", "author": "Henry David Thoreau"],
    ]

    // Real quotes from known authors — rest / recovery
    private static let breakReminders: [[String: String]] = [
        ["en": "Almost everything will work again if you unplug it for a few minutes, including you.", "vi": "Hầu hết mọi thứ sẽ hoạt động tốt trở lại nếu ngắt kết nối vài phút, kể cả bạn.", "author": "Anne Lamott"],
        ["en": "Take rest; a field that has rested gives a bountiful crop.", "vi": "Hãy nghỉ ngơi; mảnh đất được nghỉ sẽ cho mùa bội thu.", "author": "Ovid"],
        ["en": "Nature does not hurry, yet everything is accomplished.", "vi": "Thiên nhiên không vội vã, nhưng mọi thứ vẫn được hoàn thành.", "author": "Lão Tử"],
        ["en": "The time to relax is when you don't have time for it.", "vi": "Thời điểm để thư giãn chính là lúc bạn không có thời gian cho nó.", "author": "Sydney J. Harris"],
        ["en": "Sleep is the best meditation.", "vi": "Giấc ngủ là thiền định tốt nhất.", "author": "Đức Đạt Lai Lạt Ma"],
        ["en": "In every walk with nature, one receives far more than he seeks.", "vi": "Mỗi lần bước vào thiên nhiên, ta nhận được nhiều hơn những gì ta tìm kiếm.", "author": "John Muir"],
        ["en": "Tension is who you think you should be. Relaxation is who you are.", "vi": "Căng thẳng là con người bạn nghĩ mình phải là. Thư giãn là con người thật của bạn.", "author": "Tục ngữ Trung Hoa"],
        ["en": "Rest is not idleness.", "vi": "Nghỉ ngơi không phải là lười biếng.", "author": "John Lubbock"],
        ["en": "There is virtue in work and there is virtue in rest.", "vi": "Có phẩm giá trong lao động và có phẩm giá trong nghỉ ngơi.", "author": "Alan Cohen"],
        ["en": "A good rest is half the work.", "vi": "Nghỉ ngơi tốt là hoàn thành một nửa công việc.", "author": "Tục ngữ"],
        ["en": "He that can take rest is greater than he that can take cities.", "vi": "Người biết nghỉ ngơi vĩ đại hơn người chinh phục thành trì.", "author": "Benjamin Franklin"],
        ["en": "Your body is your most priceless possession. Take care of it.", "vi": "Cơ thể là tài sản quý giá nhất của bạn. Hãy chăm sóc nó.", "author": "Jack LaLanne"],
        ["en": "If you get tired, learn to rest, not to quit.", "vi": "Nếu mệt, hãy học cách nghỉ, không phải bỏ cuộc.", "author": "Banksy"],
        ["en": "Slow down and everything you are chasing will come around and catch you.", "vi": "Hãy chậm lại và mọi thứ bạn đang đuổi theo sẽ tự tìm đến bạn.", "author": "John De Paola"],
        ["en": "Within you there is a stillness and a sanctuary to which you can retreat at any time.", "vi": "Trong bạn có một sự tĩnh lặng và thánh địa nơi bạn có thể trú ẩn bất cứ lúc nào.", "author": "Hermann Hesse"],
        ["en": "Sometimes doing nothing is the most productive thing you can do.", "vi": "Đôi khi không làm gì lại là việc năng suất nhất bạn có thể làm.", "author": "Maxime Lagacé"],
        ["en": "To climb steep hills requires a slow pace at first.", "vi": "Để leo lên những ngọn đồi dốc, ban đầu cần đi chậm.", "author": "Shakespeare"],
        ["en": "Breathe deeply, until sweet air extinguishes the burn of fear in your lungs.", "vi": "Hít thở sâu, cho đến khi không khí trong lành dập tắt ngọn lửa lo âu trong lồng ngực.", "author": "Gina Greenlee"],
        ["en": "Give your stress wings and let it fly away.", "vi": "Hãy cho căng thẳng của bạn đôi cánh và để nó bay đi.", "author": "Terri Guillemets"],
        ["en": "Adopting the right attitude can convert a negative stress into a positive one.", "vi": "Thái độ đúng đắn có thể chuyển căng thẳng tiêu cực thành tích cực.", "author": "Hans Selye"],
        ["en": "For every minute you are angry you lose sixty seconds of happiness.", "vi": "Cứ mỗi phút bạn tức giận, bạn mất đi sáu mươi giây hạnh phúc.", "author": "Ralph Waldo Emerson"],
        ["en": "Almost everything will work again if you unplug it for a few minutes.", "vi": "Hầu hết mọi thứ sẽ hoạt động trở lại nếu bạn tắt máy vài phút.", "author": "Anne Lamott"],
        ["en": "Walking is man's best medicine.", "vi": "Đi bộ là thuốc tốt nhất của con người.", "author": "Hippocrates"],
        ["en": "Take care of your body. It's the only place you have to live.", "vi": "Hãy chăm sóc cơ thể — đó là nơi duy nhất bạn phải sống.", "author": "Jim Rohn"],
        ["en": "The groundwork for all happiness is good health.", "vi": "Nền tảng của mọi niềm vui là sức khỏe tốt.", "author": "Leigh Hunt"],
        ["en": "A healthy outside starts from the inside.", "vi": "Sự khỏe bên ngoài bắt đầu từ bên trong.", "author": "Robert Urich"],
        ["en": "Rest when you're weary. Refresh and renew yourself, your body, your mind, your spirit.", "vi": "Hãy nghỉ khi mệt. Làm mới bản thân — thể xác, trí óc, tinh thần.", "author": "Og Mandino"],
        ["en": "Physical fitness is the basis of all dynamic and creative intellectual activity.", "vi": "Thể lực là nền tảng của mọi hoạt động trí tuệ năng động và sáng tạo.", "author": "John F. Kennedy"],
        ["en": "When health is absent, wisdom cannot reveal itself, art cannot become manifest.", "vi": "Khi sức khỏe không còn, trí tuệ chẳng tỏa sáng, nghệ thuật chẳng thể hiện ra.", "author": "Herophilus"],
        ["en": "To keep the body in good health is a duty... otherwise we shall not be able to keep the mind strong and clear.", "vi": "Giữ cơ thể khỏe mạnh là bổn phận… nếu không trí óc khó duy trì sáng và trong.", "author": "Buddha"],
        ["en": "Sleep is the golden chain that ties health and our bodies together.", "vi": "Giấc ngủ là sợi xích vàng buộc sức khỏe với cơ thể.", "author": "Thomas Dekker"],
        ["en": "Water is the driving force of all nature.", "vi": "Nước là động lực của toàn bộ tự nhiên.", "author": "Leonardo da Vinci"],
        ["en": "Good health and good sense are two of life's greatest blessings.", "vi": "Sức khỏe tốt và lý trí minh mẫn là hai ân huệ lớn nhất đời người.", "author": "Publilius Syrus"],
        ["en": "He who has health has hope; and he who has hope has everything.", "vi": "Có sức khỏe là có hy vọng; có hy vọng là có tất cả.", "author": "Tục ngữ Ả Rập"],
        ["en": "Early to bed and early to rise, makes a man healthy, wealthy and wise.", "vi": "Ngủ sớm dậy sớm giúp con người khỏe mạnh, thịnh vượng và khôn ngoan.", "author": "Benjamin Franklin"],
    ]

    package static func getRandom(for phase: PomodoroPhase, lang: String) -> MotivationalQuote {
        let pool = phase == .focus ? focusReminders : breakReminders
        let entry = (pool.randomElement() ?? pool[0])
        let isVietnamese = lang == "Tiếng Việt"
        let text = isVietnamese ? (entry["vi"] ?? entry["en"] ?? "") : (entry["en"] ?? "")
        let author = entry["author"] ?? ""
        return MotivationalQuote(text: text, author: author)
    }
}
