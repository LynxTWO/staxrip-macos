import Foundation

/// Display of a bounded subset of declarations, never a content assessment.
enum TrackInspection {
    enum FlagState: String {
        case set = "Set", unset = "Not set", absent = "Not reported", invalid = "Invalid value"
        init(_ value: Int?) {
            switch value {
            case 1: self = .set
            case 0: self = .unset
            case nil: self = .absent
            default: self = .invalid
            }
        }
    }
    struct Role: Identifiable {
        let id, label, help: String
        let state: FlagState
    }
    static let explanation = "Flags shown: default, forced, hearing accessibility, visual accessibility and commentary. These are source declarations, not verified content or guaranteed player behavior."
    static func title(_ stream: MediaProbe.Stream) -> String {
        ContainerInspection.text(ContainerInspection.tag("title", in: stream.tags) ?? ContainerInspection.tag("name", in: stream.tags))
    }
    static func language(_ stream: MediaProbe.Stream) -> String {
        ContainerInspection.text(ContainerInspection.tag("language", in: stream.tags))
    }
    static func roles(_ stream: MediaProbe.Stream) -> [Role] {
        let definitions = [
            ("default", "Default", "A request to prefer this track when choosing among tracks. Player preferences can override it."),
            ("forced", "Forced", "A request to use this track during playback. For captions, this can request display even when captions were not explicitly enabled. Player behavior varies."),
            ("hearing_impaired", "Hearing accessibility", "The source flags this track as intended for people who are deaf or hard of hearing. Its content has not been checked."),
            ("visual_impaired", "Visual accessibility", "The source flags this track as intended for people who are blind or have low vision. Its content has not been checked."),
            ("comment", "Commentary", "The source flags this as a commentary track. Its spoken content has not been checked.")
        ]
        return definitions.map { key, label, help in
            Role(id: key, label: label, help: help, state: FlagState(stream.disposition?[key]))
        }
    }
    static func summary(_ stream: MediaProbe.Stream) -> String {
        let flags = roles(stream), set = flags.filter { $0.state == .set }.map(\.label)
        var result = "Reported flags: " + (set.isEmpty ? "none reported as set" : set.joined(separator: ", "))
        if flags.contains(where: { $0.state == .absent }) { result += ". Some flags are not reported" }
        if flags.contains(where: { $0.state == .invalid }) { result += ". Some flag values are invalid" }
        return result + "."
    }
}
