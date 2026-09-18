/// Supabase backend configuration.
///
/// The anon key is a PUBLIC key - safe to embed in client builds.
/// All data isolation is enforced server-side by Row Level Security:
/// every query is scoped to the signed-in user's shop (current_shop_id()).
class SupabaseConfig {
  static const url = 'https://izidltyssalvvsnievmq.supabase.co';
  static const anonKey = 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6Iml6aWRsdHlzc2FsdnZzbmlldm1xIiwicm9sZSI6ImFub24iLCJpYXQiOjE3ODk3MjUwODksImV4cCI6MjEwNTMwMTA4OX0.j5ooN8tuy4ULVYNm2tcsiqoMhs47hHE77cPElgjNQGk';
}
