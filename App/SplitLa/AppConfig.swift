import Foundation

/// Where the backend lives. Values come from the build configuration via Info.plist,
/// so pointing the app at another environment needs no code change.
struct AppConfig {
    let supabaseURL: URL
    let supabaseAnonKey: String

    static let current: AppConfig = {
        let info = Bundle.main.infoDictionary ?? [:]
        guard let urlString = info["SupabaseURL"] as? String, let url = URL(string: urlString),
              let key = info["SupabaseAnonKey"] as? String, !key.isEmpty
        else { fatalError("SupabaseURL and SupabaseAnonKey must be set in the build configuration") }
        return AppConfig(supabaseURL: url, supabaseAnonKey: key)
    }()
}
