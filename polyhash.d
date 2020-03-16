/// Polynomial hash for partial rehashing.
/// http://stackoverflow.com/a/42112687/21501
/// Written by Vladimir Panteleev <vladimir@thecybershadow.net>
/// Released into the Public Domain

module polyhash;

import std.range.primitives;
import std.traits;

struct PolynomialHash(Value)
if (isUnsigned!Value)
{
	Value value;   /// The hash value of the hashed string
	size_t length; /// The length of the hashed string

	// Cycle length == 2^^30 for uint, > 2^^46 for ulong
	// TODO: find primitive root modulo 2^^32, if one exists
	enum p = 269;

	/// Return p^^power (mod q).
	static Value pPower(size_t power)
	{
		/// Precalculated table for (p^^(2^^i))
		static immutable Value[size_t.sizeof * 8] power2s = (){
			Value[size_t.sizeof * 8] result;
			Value v = p;
			foreach (i; 0 .. result.length)
			{
				result[i] = v;
				v *= v;
			}
			return result;
		}();

		Value v = 1;
		foreach (b; 0 .. power2s.length)
			if ((size_t(1) << b) & power)
				v *= power2s[b];
		return v;
	}

	static typeof(this) hashString(in char[] s)
	{
		Value value;
		foreach (n; 0..s.length)
		{
			value *= p;
			value += Value(s[n]);
		}
		return typeof(this)(value, s.length);
	}

	static typeof(this) hashHashes(R)(R hashes)
		if (isInputRange!R && is(ElementType!R == typeof(this)))
	{
		typeof(this) result;
		foreach (hash; hashes)
		{
			result.value *= pPower(hash.length);
			result.value += hash.value;
			result.length += hash.length;
		}
		return result;
	}

	unittest
	{
		assert(hashString("").value == 0);
		assert(hashHashes([hashString(""), hashString("")]).value == 0);

		// "a" + "" + "b" == "ab"
		assert(hashHashes([hashString("a"), hashString(""), hashString("b")]) == hashString("ab"));

		// "a" + "bc" == "ab" + "c"
		assert(hashHashes([hashString("a"), hashString("bc")]) == hashHashes([hashString("ab"), hashString("c")]));

		// "a" != "b"
		assert(hashString("a") != hashString("b"));

		// "ab" != "ba"
		assert(hashString("ab") != hashString("ba"));
		assert(hashHashes([hashString("a"), hashString("b")]) != hashHashes([hashString("b"), hashString("a")]));

		// Test overflow
		assert(hashHashes([
					hashString("Mary"),
					hashString(" "), 
					hashString("had"),
					hashString(" "), 
					hashString("a"),
					hashString(" "), 
					hashString("little"),
					hashString(" "), 
					hashString("lamb"),
					hashString("")
				]) == hashString("Mary had a little lamb"));
	}
}

unittest
{
	PolynomialHash!uint uintTest;
	PolynomialHash!ulong ulongTest;
}
