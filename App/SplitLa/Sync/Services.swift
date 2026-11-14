import Supabase

/// Everything in the app that talks to the server, built once at launch.
struct Services {
    let auth: any AuthService
    let groups: GroupsService

    init(config: AppConfig) {
        let client = SupabaseClient(supabaseURL: config.supabaseURL, supabaseKey: config.supabaseAnonKey)
        auth = SupabaseAuthService(client: client)
        groups = GroupsService(client: client)
    }
}
