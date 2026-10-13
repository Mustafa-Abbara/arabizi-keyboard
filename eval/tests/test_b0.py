"""B0 rule baseline (roadmap P3 step 2): letter rules, clitics, keep-Latin, dictionary building."""

import pytest

from arabizi_eval import b0

LEXICON = {"words": {"shu": "شو", "beit": "بيت", "bet": "البيت", "kifak": "كيفك", "3am": "عم"},
           "keep_latin": ["meeting", "lau"]}


@pytest.fixture
def conv() -> b0.RuleConverter:
    return b0.RuleConverter(lexicon=LEXICON)


@pytest.mark.parametrize(("word", "arabic"), [
    ("ktir", "كتير"), ("mni7", "منيح"), ("ta3mel", "تعمل"), ("7abibi", "حبيبي"),
    ("ana", "أنا"), ("hayda", "هيدا"), ("bade", "بدي"), ("kbire", "كبيرة"),
    ("shhr", "شهر"),  # the h of "sh" is not a doubled h
    ("sakkar", "سكر"),  # doubled k collapses
    ("sheyfne", "شيفني"), ("kllfne", "كلفني"),  # -ne ending is "me"
    ("8ayr", "غير"), ("2ahwe", "قهوة"),  # 8 is غ and 2 is ق for many Lebanese typists
])
def test_letter_rules(word, arabic):
    assert b0.letters(word, b0.load_rules()) == arabic


@pytest.mark.parametrize(("word", "rules_give", "right"), [
    ("8ali", "غلي", "غالي"),  # a medial a can be a long vowel: letter rules drop it
    ("2alle", "قلة", "قلي"),  # final -e is ي here, ة in kbire: letter rules cannot tell
])
def test_known_limits_of_letter_rules(word, rules_give, right):
    # Documented, not hidden: these words need the dictionary (or the model).
    assert b0.letters(word, b0.load_rules()) == rules_give != right


@pytest.mark.parametrize(("prefix", "word", "joined"), [
    ("بال", "البيت", "بالبيت"), ("ل", "البيت", "للبيت"), ("لل", "البيت", "للبيت"), ("لل", "بيت", "للبيت"),
    ("و", "البيت", "والبيت"), ("ب", "البيت", "بالبيت"), ("من ال", "البيت", "من البيت"), ("ل", "محمد", "لمحمد"),
])
def test_join_clitic_never_doubles_the_article(prefix, word, joined):
    assert b0.join_clitic(prefix, word) == joined


@pytest.mark.parametrize(("arabizi", "arabic"), [
    ("kifak, shu 3am?", "كيفك، شو عم؟"),  # dictionary + punctuation
    ("bel beit", "بالبيت"),
    ("w el bet", "والبيت"),  # a run of clitics, dictionary word with its own article
    ("la el beit", "للبيت"),
    ("el meeting", "ال meeting"),  # before a kept Latin word the clitic stays separate
    ("w el meeting", "وال meeting"),
    ("bel LAU", "بال LAU"),  # kept Latin words keep their case
    ("b3at 100$ la", "بعت 100$ ل"),  # numbers untouched; a trailing clitic stays
    ("shuf www.lau.edu, @rami #lebanon 😂", "شوف www.lau.edu, @rami #lebanon 😂"),
    ("3al 7:30?", "عال 7:30؟"),
])
def test_conversion(conv, arabizi, arabic):
    assert conv.convert(arabizi) == arabic


def train_row(id_, arabizi, arabic):
    return {"id": id_, "arabizi": arabizi, "arabic": arabic, "method": "ai_checked", "split": "train"}


def test_build_lexicon_from_direct_and_clitic_alignments():
    rows = [
        train_row("ai-0001", "shu 3am ta3mel", "شو عم تعمل"),  # same number of words
        train_row("ai-0002", "ana bel beit", "أنا بالبيت"),  # bel + beit = بالبيت -> beit = بيت
        train_row("ai-0003", "ma 3ndi meeting", "ما عندي meeting"),  # meeting kept in Latin
        train_row("ai-0004", "shu ya", "شو يا"),
        train_row("ai-0005", "shu", "شوو"),  # minority spelling loses
        train_row("ai-0006", "this does not line up", "ما"),  # skipped
    ]
    lexicon = b0.build_lexicon(rows)
    assert lexicon["words"]["shu"] == "شو"
    assert lexicon["words"]["beit"] == "بيت"
    assert "meeting" in lexicon["keep_latin"] and "meeting" not in lexicon["words"]
    assert "bel" not in lexicon["words"]  # clitics are rules, not dictionary words
    assert lexicon["built_from"]["rows"] == 6 and lexicon["built_from"]["aligned_rows"] == 5


def test_dictionary_is_never_built_from_dev_or_test():
    with pytest.raises(ValueError, match="train split"):
        b0.build_lexicon([train_row("hw-0001", "shu", "شو") | {"split": "dev"}])


def test_committed_files_load():
    rules, lexicon = b0.load_rules(), b0.load_lexicon()
    assert rules["version"] == 1 and "w" in rules["clitics"]
    assert lexicon["words"] and lexicon["built_from"]["rows"] > 0
