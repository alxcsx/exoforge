using System;

namespace Exoforge
{
    /// <summary>
    /// Marks a method as a scheduled recurring background task (cron job).
    /// Executed periodically by the cluster scheduler according to the specified cron expression.
    /// Provided by the Cron extension (<c>exoforge_std_cron</c>).
    /// </summary>
    [AttributeUsage(AttributeTargets.Method, Inherited = false, AllowMultiple = false)]
    public sealed class ExoCronAttribute : Attribute
    {
        /// <summary>
        /// Standard 5-field cron expression in UTC (e.g. "0 0 * * *" for daily at midnight,
        /// "*/5 * * * *" for every 5 minutes, "0 12 * * 1-5" for weekdays at noon).
        /// Standard aliases are also supported: @daily, @hourly, @weekly, @monthly, @yearly.
        /// </summary>
        public string Schedule { get; }

        /// <summary>
        /// Optional identifier for the cron task. Defaults to the method name in snake_case.
        /// </summary>
        public string? Name { get; set; }

        /// <summary>
        /// Optional human-readable description displayed in the Studio inspector and cluster API docs.
        /// </summary>
        public string? Description { get; set; }

        /// <summary>
        /// Whether the task runs immediately when the extension starts, before the first cron trigger.
        /// Useful for seeding, warmup, or initial cache hydration. Defaults to false.
        /// </summary>
        public bool RunOnStartup { get; set; }

        /// <summary>
        /// The service this cron job belongs to, when the extension provides more than one.
        /// Defaults to the primary service.
        /// </summary>
        public string? Service { get; set; }

        public ExoCronAttribute(string schedule, string? name = null)
        {
            Schedule = schedule;
            Name = name;
        }
    }
}
