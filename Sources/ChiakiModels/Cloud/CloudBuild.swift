/// Whether this build of the app has PlayStation cloud streaming.
///
/// The `CHIAKI_CLOUD` build setting decides it, and it is off by default. A build made with `CHIAKI_CLOUD=0`
/// shows no cloud page, cloud option or cloud launch for PS Now or PS Cloud, and the core refuses every cloud
/// call.
public enum CloudBuild {
    #if CHIAKI_CLOUD
        /// `true`: this build has cloud streaming.
        public static let included = true
    #else
        /// `false`: this build leaves cloud streaming out.
        public static let included = false
    #endif
}
