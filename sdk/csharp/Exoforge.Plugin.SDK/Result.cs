using System;
using System.Collections.Generic;

namespace Exoforge.Plugin.SDK;

/// <summary>
/// Discriminated union representing the outcome of an operation: either a success value or an error reason.
/// Maps 1:1 to idiomatic Elixir {:ok, value} | {:error, reason} tuples across the host bridge.
/// </summary>
public readonly struct Result<T> : IEquatable<Result<T>>
{
    private readonly T? _value;
    private readonly string? _error;

    public bool IsSuccess { get; }

    public bool IsError => !IsSuccess;

    /// <summary>Gets the success value (or default when failed).</summary>
    public T? Value => _value;

    /// <summary>Gets the error description (or null when succeeded).</summary>
    public string? Error => _error;

    private Result(bool isSuccess, T? value, string? error)
    {
        IsSuccess = isSuccess;
        _value = value;
        _error = error;
    }

    public static Result<T> Ok(T value) => new(true, value, null);
    public static Result<T> Fail(string error) => new(false, default, error ?? "Unknown error");

    public static implicit operator Result<T>(T value) => Ok(value);

    /// <summary>Deconstruction support for C# pattern matching and tuples.</summary>
    public void Deconstruct(out bool isSuccess, out T? value, out string? error)
    {
        isSuccess = IsSuccess;
        value = _value;
        error = _error;
    }

    /// <summary>Matches against the result, returning a value depending on success or failure.</summary>
    public TOut Match<TOut>(Func<T, TOut> onOk, Func<string, TOut> onError)
    {
        if (onOk == null) throw new ArgumentNullException(nameof(onOk));
        if (onError == null) throw new ArgumentNullException(nameof(onError));

        return IsSuccess ? onOk(_value!) : onError(_error!);
    }

    public bool Equals(Result<T> other) =>
        IsSuccess == other.IsSuccess &&
        EqualityComparer<T?>.Default.Equals(_value, other._value) &&
        string.Equals(_error, other._error, StringComparison.Ordinal);

    public override bool Equals(object? obj) => obj is Result<T> other && Equals(other);

    public override int GetHashCode()
    {
        unchecked
        {
            var hash = IsSuccess.GetHashCode();
            hash = (hash * 397) ^ (_value is not null ? EqualityComparer<T>.Default.GetHashCode(_value) : 0);
            hash = (hash * 397) ^ (_error is not null ? StringComparer.Ordinal.GetHashCode(_error) : 0);
            return hash;
        }
    }

    public override string ToString() => IsSuccess ? $"Ok({_value})" : $"Error({_error})";
}

/// <summary>
/// Non-generic Result type for actions that do not produce a return payload.
/// </summary>
public readonly struct Result : IEquatable<Result>
{
    public bool IsSuccess { get; }
    public bool IsError => !IsSuccess;
    public string? Error { get; }

    private Result(bool isSuccess, string? error)
    {
        IsSuccess = isSuccess;
        Error = error;
    }

    public static Result Ok() => new(true, null);
    public static Result Fail(string error) => new(false, error ?? "Unknown error");

    public void Deconstruct(out bool isSuccess, out string? error)
    {
        isSuccess = IsSuccess;
        error = Error;
    }

    public bool Equals(Result other) =>
        IsSuccess == other.IsSuccess &&
        string.Equals(Error, other.Error, StringComparison.Ordinal);

    public override bool Equals(object? obj) => obj is Result other && Equals(other);

    public override int GetHashCode() =>
        unchecked((IsSuccess.GetHashCode() * 397) ^ (Error?.GetHashCode() ?? 0));

    public override string ToString() => IsSuccess ? "Ok" : $"Error({Error})";
}
