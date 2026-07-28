import Foundation

final class SpeechBubbleService {
    private let cacheSize = 20
    private var cache: [(key: String, message: String)] = []

    static let fallbackMessages = [
        "Hey! You've been on here a while. Time to get back to work!",
        "Still here? Your future self says thanks for taking a break!",
        "Psst... remember that thing you were supposed to do?",
        "I believe in you! Now go do something productive!",
        "Time flies when you're on \(#function)... back to work!",
        "You've got goals. This isn't one of them.",
        "Your to-do list misses you.",
        "What if you worked on your project for just 5 minutes?",
        "Challenge: close this tab. I dare you.",
        "I see you. Now go be great.",
    ]

    func nudgeMessage(host: String, secondsOver: Double) async -> String {
        let key = "\(host)-\(Int(secondsOver / 60))"
        if let cached = cache.first(where: { $0.key == key })?.message {
            return cached
        }

        guard let apiKey = Keychain.load(forKey: "anthropicAPIKey"), !apiKey.isEmpty else {
            return randomFallback(host: host)
        }

        let minutesOver = Int(secondsOver / 60)
        let prompt = """
        You are a cute, encouraging pixel-art pet companion in a focus app. The user has spent \(minutesOver) minute(s) over their daily budget on \(host). Write ONE short, friendly, slightly witty speech bubble message (max 20 words) to nudge them back to being productive. No hashtags, no emojis, no quotes. Just the message.
        """

        do {
            let message = try await AnthropicClient.complete(prompt: prompt, apiKey: apiKey)
            store(key: key, message: message)
            return message
        } catch {
            return randomFallback(host: host)
        }
    }

    private func randomFallback(host: String) -> String {
        let msgs = Self.fallbackMessages
        return msgs[Int.random(in: 0..<msgs.count)]
    }

    private func store(key: String, message: String) {
        if cache.count >= cacheSize { cache.removeFirst() }
        cache.append((key: key, message: message))
    }
}
