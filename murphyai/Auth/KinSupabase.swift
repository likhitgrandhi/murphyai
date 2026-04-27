import Foundation
import Supabase

// Single shared client. The SDK uses Keychain for session storage by default on macOS.
// The publishable (anon) key is safe to embed in client apps.
let kinSupabase = SupabaseClient(
    supabaseURL: URL(string: "https://heuncqqngkypwnjyhikw.supabase.co")!,
    supabaseKey: "sb_publishable_K_NlaaxxEWJkizozvAlBTQ_gpS66sJz",
    options: SupabaseClientOptions(
        auth: SupabaseClientOptions.AuthOptions(emitLocalSessionAsInitialSession: true)
    )
)
