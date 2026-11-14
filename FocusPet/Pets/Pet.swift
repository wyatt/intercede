import Foundation

/// A companion: its art, its name, and what it says. `%@` in a phrase is replaced by the site.
struct Pet: Identifiable {
    enum Art {
        case bundled                      // ships in the app (always available)
        case petdex(spritesheet: URL)     // downloaded once and cached
    }

    let slug: String
    let name: String
    let catchphrase: String
    let phrases: [String]
    let art: Art

    var id: String { slug }

    func randomPhrase(host: String) -> String {
        let phrase = phrases.randomElement() ?? ""
        return phrase.replacingOccurrences(of: "%@", with: host)
    }
}

extension Pet {
    static let stAlphonsus = Pet(
        slug: "bishop",
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
        art: .bundled
    )

    static let hazel = Pet(
        slug: "little-deer",
        name: "Hazel the Fawn",
        catchphrase: "Oh deer, not this again!",
        phrases: [
            "Every minute counts — let's not fawn over %@.",
            "Antler-ly unacceptable! Back to your task.",
            "Let's prance back to something productive.",
            "I'm not mad, just a little doe-sappointed.",
            "The forest is quiet. Perfect for focusing.",
            "One small leap back to work — you've got this.",
            "Your goals are waiting in the meadow. Let's go!",
            "Deer friend, close the tab!",
        ],
        art: .petdex(spritesheet: URL(string: "https://assets.petdex.dev/pets/little-deer-04f24a352c67/sprite.webp")!)
    )

    static let maple = Pet(
        slug: "red-panda",
        name: "Maple the Red Panda",
        catchphrase: "Paws off the scroll!",
        phrases: [
            "Even I only nap half the day. Time to work!",
            "Climb back up to your goals!",
            "Tails up! One task at a time.",
            "%@ will still be there later. Your focus won't.",
            "I'm red with concern. Back to work, please!",
            "Cozy up with your project instead.",
            "A little progress beats a lot of scrolling.",
            "Let's bamboo-st through that to-do list!",
        ],
        art: .petdex(spritesheet: URL(string: "https://assets.petdex.dev/pets/red-panda-92e0542b04d2/sprite.webp")!)
    )

    static let pip = Pet(
        slug: "penguin-chick",
        name: "Pip the Penguin",
        catchphrase: "Waddle back to work!",
        phrases: [
            "Chill out on %@, warm up on your work.",
            "Let's slide back into focus!",
            "I'm just a chick, and even I know this is a detour.",
            "Huddle up with your to-do list.",
            "Ice to see you — now let's get going!",
            "Small steps! That's how penguins cross the whole ice.",
            "Fish later. Focus now.",
            "Every great swim starts with one paddle. Start your task!",
        ],
        art: .petdex(spritesheet: URL(string: "https://assets.petdex.dev/pets/penguin-chick-30034f1536e7/sprite.webp")!)
    )

    static let bramble = Pet(
        slug: "hedgehog",
        name: "Bramble the Hedgehog",
        catchphrase: "Let's get to the point!",
        phrases: [
            "This is getting a little prickly. Back to work?",
            "Curl up with your project, not with %@.",
            "Slow and steady still gets things done.",
            "I'm small, but my standards are sharp.",
            "Snuffle out one thing to finish, and do it now.",
            "A few focused minutes, then a well-earned snack.",
            "No need to bristle. Just close the tab!",
            "Hedge your bets on finishing that task.",
        ],
        art: .petdex(spritesheet: URL(string: "https://assets.petdex.dev/pets/hedgehog-6327930213ab/sprite.webp")!)
    )

    static let boba = Pet(
        slug: "blue-boba-axolotl",
        name: "Boba the Axolotl",
        catchphrase: "I axolotl you to get back to work!",
        phrases: [
            "I can regrow a leg. I can't regrow your afternoon.",
            "Sip, breathe, and get back to it.",
            "Let's bubble up some productivity!",
            "Stay chill, stay focused.",
            "%@ can wait. Your work is ready now.",
            "Every tiny step forward counts — even with tiny legs.",
            "Smile! Then close the tab.",
            "Pearls of wisdom: do the hard thing first.",
        ],
        art: .petdex(spritesheet: URL(string: "https://assets.petdex.dev/pets/blue-boba-axolotl-95e9366e6389/sprite.webp")!)
    )

    static let roster: [Pet] = [stAlphonsus, hazel, maple, pip, bramble, boba]
}
