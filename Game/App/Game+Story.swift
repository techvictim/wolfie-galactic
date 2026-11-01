import Foundation

/// The Red Glitch story: six short cards, the first time you press Play and any time from the
/// pause menu. Wolfie and Gizmo tell it, in their Wolfie Military voices where the words match.
struct StoryCard {
    /// Who's talking, and their picture.
    let who: String
    let picture: String
    let text: String
    /// The Wolfie Military voice clip that says these words, if there is one.
    let clip: String?
}

extension Game {
    static let story: [StoryCard] = [
        StoryCard(who: "Wolfie", picture: "crew-wolfie",
                  text: "This is Wolfie World. Everyone was happy here… until the Red Glitch came.", clip: nil),
        StoryCard(who: "Gizmo", picture: "crew-gizmo",
                  text: "Oopsie! I made a helper program to fix the buildings. But it glitched! Now it's the Red Glitch!", clip: "st2"),
        StoryCard(who: "Wolfie", picture: "robocat",
                  text: "The Glitch hides inside buildings, on every planet. The red, glowing ones are Glitch Nests. They make robo-cats!", clip: nil),
        StoryCard(who: "Wolfie", picture: "crew-wolfie",
                  text: "Don't worry. Everyone got out safe, and they're waiting up in the hills. But nobody can go home until the Glitch is gone.", clip: "st4"),
        StoryCard(who: "Wolfie", picture: "crew-wolfie",
                  text: "Wolves can smell the Glitch. That's why we're Wolfie Military! Knock down the red buildings, and our builder bots make them clean again.", clip: "st5"),
        StoryCard(who: "Gizmo", picture: "crew-gizmo",
                  text: "Let's fix my glitch! Wolfie Military, go, go, go!", clip: "st6"),
    ]

    var storyCard: StoryCard { Game.story[min(max(storyIndex, 0), Game.story.count - 1)] }

    func openStory() {
        if screen != .story { storyReturn = screen }
        screen = .story
        storyIndex = 0
        sayStoryCard()
    }

    func updateStory(_ frame: InputFrame) {
        if frame.cancel || frame.pause {
            closeStory()
        } else if frame.confirm || frame.menuStep > 0 {
            nextStoryCard()
        } else if frame.menuStep < 0 && storyIndex > 0 {
            storyIndex -= 1
            sayStoryCard()
        }
    }

    func nextStoryCard() {
        Sound.shared.play("menu-move")
        if storyIndex >= Game.story.count - 1 {
            closeStory()
        } else {
            storyIndex += 1
            sayStoryCard()
        }
    }

    private func sayStoryCard() {
        let card = storyCard
        if let clip = card.clip {
            Voices.shared.say(clip, as: card.who.lowercased(), cooldown: 0, interrupt: true)
        }
    }

    func closeStory() {
        Sound.shared.play("menu-select", volume: 0.7)
        if storyReturn == .paused {
            screen = .paused
            menuIndex = menuItems.firstIndex(of: .story) ?? 0
        } else {
            activate(.resume)
        }
    }
}
