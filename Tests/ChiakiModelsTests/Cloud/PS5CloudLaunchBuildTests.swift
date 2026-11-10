import ChiakiModels
import Foundation
import Testing

@Test func psCloudTitleFollowsTheBuildSetting() {
    let game = CloudGame(productId: "EP9000-PPSA01234_00-ASTROBOT00000000", name: "Astro Bot")
    let request = try? CloudLaunchRequest(accountID: UUID(), game: game)
    #expect((request != nil) == PS5CloudLaunchBuild.included)
}

@Test func psNowTitleFollowsItsOwnBuildSetting() {
    let game = CloudGame(
        productId: "EP9000-CUSA01234_00-CLASSIC000000000",
        name: "Classic",
        platform: "PS4",
        streamServiceType: "psnow"
    )
    let request = try? CloudLaunchRequest(accountID: UUID(), game: game)
    #expect((request != nil) == PS4CloudLaunchBuild.included)
}

@Test func noCloudTitleLaunchesWithoutTheCloudBuild() {
    #expect(!PS5CloudLaunchBuild.included || CloudBuild.included)
    #expect(!PS4CloudLaunchBuild.included || CloudBuild.included)
}
