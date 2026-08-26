namespace MediaFlowMonitor.Licensing;

/// Port identic din SupabaseConfig.swift — ACEEAȘI bază de date Supabase,
/// folosită de tot ecosistemul GDC (niciun backend nou). Cheia "anon" e
/// sigură de comis: RLS blochează orice acces direct, singura funcție
/// apelabilă e `is_license_revoked` (returnează strict true/false).
public static class SupabaseConfig
{
    public const string ProjectURL = "https://jvxrclpyngdcqnbwvtfn.supabase.co";
    public const string AnonKey = "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6Imp2eHJjbHB5bmdkY3FuYnd2dGZuIiwicm9sZSI6ImFub24iLCJpYXQiOjE3ODcwODMxMDksImV4cCI6MjEwMjY1OTEwOX0.uCLgrVPLhovwdBc82KermRbtWykquWoJmg9WmGk2L-s";
}
