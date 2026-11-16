import Foundation

/// A companion: its art, its name, and what it says. `%@` in a phrase is replaced by the site.
struct Patron: Identifiable {
    let slug: String
    let name: String
    let catchphrase: String
    let phrases: [String]
    /// Bundled sprite sheet `<sheetName>.png` in the standard Intercede layout (see SpriteSheet.standard).
    let sheetName: String

    var id: String { slug }

    /// A random phrase for `host`. Without a host (e.g. Test Nudge), only phrases that don't name a site.
    func randomPhrase(host: String?) -> String {
        guard let host else {
            return phrases.filter { !$0.contains("%@") }.randomElement() ?? catchphrase
        }
        return (phrases.randomElement() ?? catchphrase).replacingOccurrences(of: "%@", with: host)
    }
}

extension Patron {
    static let stAlphonsus = Patron(
        slug: "liguori",
        name: "St. Alphonsus Liguori",
        catchphrase: "This is not Liguorian!",
        phrases: [
            "I vowed never to waste a moment. Shall we try it together?",
            "Prayer is the great means. Scrolling is not.",
            "I wrote over a hundred books. You can finish one task.",
            "Every moment is a gift. Don't hand this one to %@.",
            "Close the tab, my child. Your duties are waiting, and so is grace.",
            "I left the law courts for something better. You can leave %@.",
            "Be gentle with yourself — then get back to work.",
            "A little diligence now spares a great deal of worry later.",
            "Offer up the next hour. You'll be glad you did.",
            "Do what you are doing, and do it well.",
            "I lived to ninety without %@. You'll survive an afternoon.",
            "Time is precious. Spend it on what you'll be glad you did.",
        ],
        sheetName: "liguori"
    )

    static let isidore = Patron(
        slug: "isidore",
        name: "St. Isidore of Seville",
        catchphrase: "Even the patron of the internet says log off!",
        phrases: [
            "I tried to write down all human knowledge. It didn't include %@.",
            "Twenty books of Etymologies, and not one about doomscrolling.",
            "Read to learn, not to lose the afternoon.",
            "Close the tab; open a book.",
            "Knowledge is gathered slowly. Distraction arrives all at once.",
            "I'd bless this connection, but you have work to do.",
            "Seventh-century advice, still good: do your work first.",
            "An encyclopedia is built one entry at a time. So is your project.",
        ],
        sheetName: "isidore"
    )

    static let clare = Patron(
        slug: "clare",
        name: "St. Clare of Assisi",
        catchphrase: "As patron of screens, I've seen enough.",
        phrases: [
            "I saw Mass on my convent wall from my sickbed. You can look away from %@.",
            "What you do, may you always do — and never abandon it for %@.",
            "Love poverty — especially poverty of tabs.",
            "Gaze upon something worthwhile.",
            "Go forth in peace — and close the tab.",
            "Simplicity is a gift. Give yourself some.",
            "Less screen, more serene.",
            "Patience, dear one. Your work is waiting.",
        ],
        sheetName: "clare"
    )

    static let benedict = Patron(
        slug: "benedict",
        name: "St. Benedict",
        catchphrase: "Idleness is the enemy of the soul!",
        phrases: [
            "Ora et labora. Right now, mostly labora.",
            "Listen with the ear of your heart — not to %@.",
            "My Rule has seventy-three chapters. None of them are about %@.",
            "Always we begin again. Begin your work now.",
            "Keep your hours. This isn't one of them.",
            "A little rule brings a lot of peace.",
            "The bell has rung. Back to work!",
            "Stability, my friend. Stay with your task.",
        ],
        sheetName: "benedict"
    )

    static let aquinas = Patron(
        slug: "aquinas",
        name: "St. Thomas Aquinas",
        catchphrase: "I answer that: close the tab.",
        phrases: [
            "Objection: %@ is fun. I answer that: so is finished work.",
            "I kept four scribes busy at once. You can manage one tab.",
            "They called me the Dumb Ox. Oxen plow straight furrows.",
            "The Summa wasn't written in a day. Start your part of it.",
            "Wonder is the desire for knowledge. %@ is not wonder.",
            "The patron of students says: study now.",
            "Reason suggests one task at a time.",
            "First principles: do the work, then rest.",
        ],
        sheetName: "aquinas"
    )

    /// Patrons appear in the app once their sheet is bundled (see `PatronLibrary.availablePatrons`).
    static let roster: [Patron] = [stAlphonsus, isidore, clare, benedict, aquinas]
}
