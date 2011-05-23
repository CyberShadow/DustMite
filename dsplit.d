/// Very simplistic D source code "parser"
/// Written by Vladimir Panteleev <vladimir@thecybershadow.net>
/// Released into the Public Domain

module dsplit;

import std.file;
import std.path;
import std.string;
import std.ctype;
import std.array;
debug import std.stdio;

struct Entity
{
	string header;
	Entity[] children;
	string footer;

	bool isPair; // internal hint

	alias header filename; // for level 0
}

Entity[] loadFiles(string dir)
{
	Entity[] set;
	foreach (path; listdir(dir, "*"))
		if (isfile(path))
		{
			assert(path.startsWith(dir));
			auto name = path[dir.length+1..$];
			set ~= Entity(name, loadFile(path), null);
		}
	return set;
}

private:

Entity[] loadFile(string path)
{
	string contents = cast(string)read(path);
	switch (getExt(path))
	{
	case "d":
		debug writeln("Loading ", path);
		return parseD(contents);
	// One could add custom splitters for other languages here - for example, a simple line/word/character splitter for most text-based formats
	default:
		return [Entity(contents, null, null)];
	}
}

Entity[] parseD(string s)
{
	size_t i = 0, lastFooterStart;
	enum NONE = size_t.max;

	/// Moves i forward over first series of EOL characters, or until first non-whitespace character
	void skipEOL()
	{
		// TODO: skip end-of-line comments, too
		while (i < s.length && iswhite(s[i]))
		{
			if (s[i] == '\r' || s[i] == '\n')
			{
				while (i < s.length && (s[i] == '\r' || s[i] == '\n'))
					i++;
				return;
			}
			i++;
		}
	}

	Entity[] parseScope(bool topLevel)
	{
		size_t start = i;
		size_t wsStart = i;

		Entity makeEntity(size_t headerEnd, Entity[] entities, size_t footerStart)
		{
			Entity result = Entity(s[start..headerEnd], entities, footerStart!=NONE ? s[footerStart..i] : null);
			start = wsStart = footerStart!=NONE ? i : headerEnd;
			return result;
		}

		Entity[] entities;

		while (i < s.length)
		{
			switch (s[i])
			{
				case ';': // end of entity
				{
					auto entityEnd = i;
					i++; skipEOL();
					entities ~= makeEntity(entityEnd, null, entityEnd);
					break;
				}
				case '{':
				{
					auto entityHead = makeEntity(wsStart, null, NONE);
					i++; skipEOL();
					auto headerEnd = i;
					auto children = parseScope(false);
					skipEOL();

					auto entityBody = makeEntity(headerEnd, children, lastFooterStart);

					entities ~= Entity(null, [entityHead, entityBody], null, true);
					break;
				}
				case '}':
				{
					if (topLevel) // stray } or bug, treat as normal character
					{
						i++;
						wsStart = i;
						break;
					}

					if (start != wsStart)
					{
						// there was some unterminated stuff at the end of the current scope
						// TODO: EOL separation here
						entities ~= makeEntity(i, null, NONE);
					}
					lastFooterStart = start;
					i++;
					return postProcessD(entities);
				}
				case '\'':
				{
					i++;
					if (s[i] == '\\')
						i+=2;
					while (s[i] != '\'')
						i++;
					i++;
					wsStart = i;
					break;
				}
				case '"':
				{
					if (s[i-1] == 'r')
					{
						i++;
						while (s[i] != '"')
							i++;
						i++;
					}
					else
					{
						i++;
						while (s[i] != '"')
						{
							if (s[i] == '\\')
								i+=2;
							else
								i++;
						}
						i++;
					}
					wsStart = i;
					break;
				}
				case '`':
				{
					i++;
					while (s[i] != '`')
						i++;
					i++;
					wsStart = i;
					break;
				}
				case '/':
				{
					i++;
					if (s[i] == '/')
					{
						while (s[i] != '\r' && s[i] != '\n')
							i++;
					}
					else
					if (s[i] == '*')
					{
						i+=3;
						while (s[i-2] != '*' || s[i-1] != '/')
							i++;
					}
					else
					if (s[i] == '+')
					{
						i++;
						int commentLevel = 1;
						while (commentLevel)
						{
							if (s[i] == '/' && s[i+1]=='+')
								commentLevel++, i+=2;
							else
							if (s[i] == '+' && s[i+1]=='/')
								commentLevel--, i+=2;
							else
								i++;
						}
					}
					else
						i++;
					wsStart = i;
					break;
				}
				// TODO: token strings
				// TODO: parens
				// TODO: lists?
				default:
				{
					def:
					if (!iswhite(s[i]))
						wsStart = i+1;
					i++;
					break;
				}
			}

		}

		if (start != i)
			entities ~= makeEntity(i, null, NONE);
		return postProcessD(entities);
	}

	return parseScope(true);
}

/// Group together consecutive entities which might represent a single language construct
/// There is no penalty for false positives, so accuracy is not very important
Entity[] postProcessD(Entity[] entities)
{
	for (int i=0; i<entities.length; i++)
	{
		if (i+3 <= entities.length && entities[i].isPair && entities[i+1].isPair && entities[i+2].isPair && (
			(entities[i].children[0].header.endsWithWord("in")  && entities[i+1].children[0].header.endsWithWord("out") && entities[i+2].children[0].header.endsWithWord("body")) ||
			(entities[i].children[0].header.endsWithWord("out") && entities[i+1].children[0].header.endsWithWord("in")  && entities[i+2].children[0].header.endsWithWord("body"))
		))
			entities.replaceInPlace(i, i+3, [Entity(null, entities[i..i+3].dup, null)]);
		else
		if (i+2 <= entities.length && entities[i].isPair && entities[i+1].isPair && (
			(entities[i].children[0].header.endsWithWord("in")  && entities[i+1].children[0].header.endsWithWord("body")) ||
			(entities[i].children[0].header.endsWithWord("out") && entities[i+1].children[0].header.endsWithWord("body")) ||
			(entities[i].children[0].header.endsWithWord("try") && entities[i+1].children[0].header.startsWithWord("catch")) ||
			(entities[i].children[0].header.endsWithWord("try") && entities[i+1].children[0].header.startsWithWord("finally"))
		))
			entities.replaceInPlace(i, i+2, [Entity(null, entities[i..i+2].dup, null)]);
		else
		if (i+2 <= entities.length && entities[i+1].header.startsWithWord("while") && entities[i+1].children is null && (
			(entities[i].isPair && entities[i].children[0].header.isWord("do")) ||
			(entities[i].header.startsWithWord("do"))
		))
			entities.replaceInPlace(i, i+2, [Entity(null, entities[i..i+2].dup, null)]);
	}

	return entities;
}

string stripD(string s)
{
	// TODO: strip D comments, too
	return strip(s);
}

bool startsWithWord(string s, string word)
{
	s = stripD(s);
	return s.startsWith(word) && (s.length == word.length || !isalnum(s[word.length]));
}

bool endsWithWord(string s, string word)
{
	s = stripD(s);
	return s.endsWith(word) && (s.length == word.length || !isalnum(s[$-word.length-1]));
}

bool isWord(string s, string word)
{
	// TODO: fixme
	return s.startsWithWord(word) || s.endsWithWord(word);
}
