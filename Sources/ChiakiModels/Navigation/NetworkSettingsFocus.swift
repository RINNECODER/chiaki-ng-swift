/// The controls of the network settings that controller navigation moves between by hand.
public enum NetworkSettingsFocus: Hashable, Sendable {
    /// The unicast sweep toggle.
    case sweep

    /// The subnets text field.
    case subnets
    /// The macOS toggle for pausing AWDL while streaming over Wi-Fi.
    case steadyWiFi
}
