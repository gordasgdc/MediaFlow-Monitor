using System;
using System.Security.Cryptography;
using System.Text;
using Org.BouncyCastle.Crypto.Parameters;
using Org.BouncyCastle.Crypto.Signers;

namespace MediaFlowMonitor.Licensing;

/// Port C# al LicenseCore.swift (byte-for-byte pe format de payload, Base32
/// și cheia publică) — ACEEAȘI cheie Ed25519 hardcodată în tot ecosistemul
/// GDC, ca un cod generat din GenerateSerialView.swift (Furnizor, Mac) să
/// fie verificat identic aici. Doar cheia PUBLICĂ — cheia privată rămâne
/// exclusiv pe mașina lui Cristi.
///
/// Verificare Ed25519: .NET nu are suport Ed25519 nativ pe Windows (CNG nu
/// îl expune) — folosim BouncyCastle.Cryptography (pur managed, aceeași
/// bibliotecă folosită de nenumărate proiecte .NET pentru exact acest caz).
public static class LicenseCore
{
    public readonly record struct Payload(long ExpiresAt, bool MachineLocked);

    public enum ValidationError { MalformedCode, BadSignature, WrongProduct, WrongMachine, Expired }

    private const string PublicKeyBase64 = "I1h23MNMRbOhc0ObKJrfa3oFHKA9w+SzbNrroAIy8hs=";
    private const int PayloadSize = 22;

    public static (Payload? payload, ValidationError? error) Validate(string serial, string expectedProductID)
    {
        var packed = Base32Decode(serial);
        if (packed == null || packed.Length != PayloadSize + 64)
            return (null, ValidationError.MalformedCode);

        var payloadBytes = packed[..PayloadSize];
        var signature = packed[PayloadSize..];

        byte[] publicKeyRaw;
        try { publicKeyRaw = Convert.FromBase64String(PublicKeyBase64); }
        catch { return (null, ValidationError.MalformedCode); }

        bool signatureValid;
        try
        {
            var publicKeyParams = new Ed25519PublicKeyParameters(publicKeyRaw, 0);
            var verifier = new Ed25519Signer();
            verifier.Init(forSigning: false, publicKeyParams);
            verifier.BlockUpdate(payloadBytes, 0, payloadBytes.Length);
            signatureValid = verifier.VerifySignature(signature);
        }
        catch { return (null, ValidationError.MalformedCode); }

        if (!signatureValid) return (null, ValidationError.BadSignature);

        var storedProductHash = payloadBytes[0..4];
        var expectedProductHash = ProductHash(expectedProductID);
        if (!storedProductHash.AsSpan().SequenceEqual(expectedProductHash))
            return (null, ValidationError.WrongProduct);

        long expiresAt = 0;
        for (int i = 4; i < 12; i++) expiresAt = (expiresAt << 8) | payloadBytes[i];

        var storedMachineHash = payloadBytes[16..22];
        bool isMachineLocked = Array.Exists(storedMachineHash, b => b != 0);
        if (isMachineLocked && !storedMachineHash.AsSpan().SequenceEqual(MachineID.HashBytes))
            return (null, ValidationError.WrongMachine);

        if (expiresAt != 0 && expiresAt < DateTimeOffset.UtcNow.ToUnixTimeSeconds())
            return (null, ValidationError.Expired);

        return (new Payload(expiresAt, isMachineLocked), null);
    }

    private static byte[] ProductHash(string productID)
    {
        var hash = SHA512.HashData(Encoding.UTF8.GetBytes(productID));
        return hash[..4];
    }

    // MARK: - Base32 (aceeași variantă custom, fără padding, ca pe Mac)

    private const string Base32Alphabet = "ABCDEFGHIJKLMNOPQRSTUVWXYZ234567";

    public static string Base32Encode(byte[] data)
    {
        int bits = 0, value = 0;
        var output = new StringBuilder();
        foreach (var b in data)
        {
            value = (value << 8) | b;
            bits += 8;
            while (bits >= 5)
            {
                output.Append(Base32Alphabet[(value >> (bits - 5)) & 0x1F]);
                bits -= 5;
            }
        }
        if (bits > 0)
            output.Append(Base32Alphabet[(value << (5 - bits)) & 0x1F]);
        return output.ToString();
    }

    public static byte[]? Base32Decode(string input)
    {
        var cleaned = input.ToUpperInvariant().Replace("-", "").Replace(" ", "").Replace("=", "");
        int bits = 0, value = 0;
        var output = new System.Collections.Generic.List<byte>();
        foreach (var ch in cleaned)
        {
            int index = Base32Alphabet.IndexOf(ch);
            if (index < 0) return null;
            value = (value << 5) | index;
            bits += 5;
            if (bits >= 8)
            {
                output.Add((byte)((value >> (bits - 8)) & 0xFF));
                bits -= 8;
            }
        }
        return output.ToArray();
    }
}
