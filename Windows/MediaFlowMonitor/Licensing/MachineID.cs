using System.Security.Cryptography;
using System.Text;
using Microsoft.Win32;

namespace MediaFlowMonitor.Licensing;

/// Echivalentul MachineID.swift, adaptat la Windows — NU trebuie să
/// folosească aceeași sursă de entropie ca Mac (IOPlatformUUID vs.
/// MachineGuid sunt concepte diferite pe fiecare OS). Contează doar ca
/// hash-ul rezultat să fie STABIL pe aceeași mașină și că Furnizorul
/// (GenerateSerialView.swift) tratează string-ul afișat ca opac — clientul
/// îl copiază din `MachineID.Display` și îl lipește direct în câmpul
/// "ID calculator" din Furnizor, care doar Base32-decodează string-ul
/// primit (nu re-hashează), deci schema de hashing per-platformă poate
/// diferi liber, câtă vreme Base32 encode/decode rămân identice (verificat
/// împotriva LicenseCore.swift/GenerateSerialView.swift, 2026-08-26).
///
/// Sursă: `HKLM\SOFTWARE\Microsoft\Cryptography\MachineGuid` — GUID stabil
/// generat de Windows la instalare, citibil fără elevare, NU se schimbă la
/// reinstalarea de drivere/upgrade minor (spre deosebire de alte ID-uri
/// hardware care pot varia).
public static class MachineID
{
    private static string RawMachineGuid()
    {
        try
        {
            using var key = Registry.LocalMachine.OpenSubKey(@"SOFTWARE\Microsoft\Cryptography");
            return key?.GetValue("MachineGuid") as string ?? "windows-machine-id-unavailable";
        }
        catch { return "windows-machine-id-unavailable"; }
    }

    public static byte[] HashBytes => SHA512.HashData(Encoding.UTF8.GetBytes(RawMachineGuid()))[..6];

    public static string Display => LicenseCore.Base32Encode(HashBytes);
}
