/// Whether this build of the app may start PS Now launches.
///
/// The `CHIAKI_PS4_CLOUD_LAUNCH` build setting decides it, and it is off by default. A build made with
/// `CHIAKI_PS4_CLOUD_LAUNCH=0` keeps PS Now titles listed but offers no way to start them, and the core refuses
/// them too. PS Cloud titles are gated by ``PS5CloudLaunchBuild`` instead, and neither launches without
/// ``CloudBuild``.
public enum PS4CloudLaunchBuild {
    #if CHIAKI_PS4_CLOUD_LAUNCH
        /// ``CloudBuild/included``: this build may start PS Now launches when it has cloud streaming.
        public static let included = CloudBuild.included
    #else
        /// `false`: this build refuses PS Now launches.
        public static let included = false
    #endif
}
