using System;

namespace Exoforge.Client
{
    /// <summary>
    /// Exponential backoff with a ceiling, for reconnect delays.
    ///
    /// Unity-free on purpose: the doubling and the cap are the only part with branches, so they can
    /// be tested without a running player loop.
    /// </summary>
    public static class ExoBackoff
    {
        /// <summary>
        /// Delay before attempt <paramref name="attempt"/> (0-based), doubling from
        /// <paramref name="baseSeconds"/> and never exceeding <paramref name="maxSeconds"/>.
        /// </summary>
        public static TimeSpan Delay(int attempt, double baseSeconds, double maxSeconds)
        {
            if (attempt < 0) attempt = 0;
            if (baseSeconds <= 0) baseSeconds = 1d;
            if (maxSeconds < baseSeconds) maxSeconds = baseSeconds;

            // Clamped before the shift: Math.Pow overflows to infinity for a large attempt, and
            // Math.Min would then return the cap only by luck.
            double delay = attempt >= 32 ? maxSeconds : baseSeconds * Math.Pow(2, attempt);

            return TimeSpan.FromSeconds(Math.Min(delay, maxSeconds));
        }
    }
}
