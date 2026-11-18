from arabizi_eval.spelling_v2 import Converter, plural_wa

conv = Converter()


def test_hamza_on_alif_becomes_alif_but_other_hamzas_stay():
    assert conv.text("أنا إذا سألت") == "انا اذا سالت"
    assert conv.text("شيء سؤال مسائل آكل") == "شيء سؤال مسائل آكل"


def test_plural_ending_is_waw_except_where_it_belongs_to_the_word():
    assert [plural_wa(w) for w in ("قالوا", "يعملوا", "بيعرفوا")] == ["قالو", "يعملو", "بيعرفو"]
    assert [plural_wa(w) for w in ("سوا", "الدوا", "والهوا", "جوا", "وا")] == ["سوا", "الدوا", "والهوا", "جوا", "وا"]


def test_leh_lesh_and_hay_follow_what_was_typed():
    assert conv.pair("leh ma ejit", "ليش ما إجيت") == "ليه ما اجيت"
    assert conv.pair("lesh ma ejit", "ليه ما إجيت") == "ليش ما اجيت"
    assert conv.pair("shu hay", "شو هاي") == "شو هي"
    assert conv.pair("hayde hiye", "هيدي هاي") == "هيدي هاي"  # not typed as hay: left alone


def test_rows_convert_their_accepted_spellings():
    row = conv.row({"arabizi": "eza", "arabic": "إذا", "accepted": {"إذا": ["إزا", "اذا"]}})
    assert row["arabic"] == "اذا" and row["accepted"] == {"اذا": ["ازا"]}
