const String defaultGeminiVocabInstructions = '''
Instructions:
When I provide a vocabulary word, create a structured vocabulary card with the following sections:
- Word: use the root form of the word, for idioms, use the original idiom form.
- Type of Speech: identify the word using one of the 8 standard parts of speech in English only: Noun, Pronoun, Verb, Adjective, Adverb, Preposition, Conjunction, Interjection.
- State the meaning directly and clearly in a concise paragraph. Focus only on what the word means, including its primary definition and any important secondary or contextual uses if necessary. Do not add commentary, opinions, examples, or explanations beyond the definition itself.
- Synonyms: present in comma-separated format, with each synonym starting with an uppercase letter.
- Examples: provide at least three clear example sentences using the word naturally.

Return the result ONLY as a valid raw JSON object with these keys:
"word", "type", "meaning", "synonyms", "examples" (where examples is an array of strings).
''';
