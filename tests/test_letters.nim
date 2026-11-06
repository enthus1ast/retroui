## Tests of letters (#[tags]#, amounts in words) and sealed files.

import std/[tables, strutils, times]
import retroui/[templates, vault]

block wordsBlock:
  doAssert numberWords(0) == "Zero"
  doAssert numberWords(790) == "Seven Hundred Ninety"
  doAssert numberWords(1250) == "One Thousand Two Hundred Fifty"
  doAssert numberWords(21_000_015) == "Twenty-One Million Fifteen"
  doAssert amountWords(790) == "Seven Hundred Ninety Omani Rials"
  doAssert amountWords(1) == "One Omani Rial"
  doAssert amountWords(790.5) == "Seven Hundred Ninety Omani Rials and Five Hundred Baisa"
  doAssert amountWords(0.25) == "Two Hundred Fifty Baisa"
  doAssert arabicNumberWords(790) == "سبعمائة وتسعون", arabicNumberWords(790)
  doAssert arabicNumberWords(21) == "واحد وعشرون"
  doAssert arabicNumberWords(1500) == "ألف وخمسمائة"
  doAssert arabicNumberWords(2000) == "ألفان"
  doAssert arabicNumberWords(3000) == "ثلاثة آلاف"
  doAssert arabicNumberWords(15000) == "خمسة عشر ألفاً"
  doAssert amountWords(790, arabic = true) == "سبعمائة وتسعون ريالاً عمانياً", amountWords(790, arabic = true)
  doAssert amountWords(1, arabic = true) == "ريال عماني واحد"
  doAssert amountWords(2, arabic = true) == "ريالان عمانيان"
  doAssert amountWords(5, arabic = true) == "خمسة ريالات عمانية"
  doAssert amountWords(300, arabic = true) == "ثلاثمائة ريال عماني"
  doAssert amountWords(610.5, arabic = true) == "ستمائة وعشرة ريالات عمانية وخمسمائة بيسة",
    amountWords(610.5, arabic = true)

block tagsBlock:
  let values = {"name": "Maryam Al Hinai", "totalsalary": "790.000",
                "joiningdate": "2018-09-02", "hotelname": "Sohar Hotel"}.toTable
  let answers = {"addressedto": "Bank Muscat"}.toTable
  let text = "To #[?Addressed to]#: #[Name]# of #[Hotel Name]# earns OMR #[Total Salary|n3]# " &
             "(#[Total Salary|words]#) since #[Joining Date|long]# / #[joining_date|date]# " &
             "#[Unknown]# #[Total Salary|words-ar]# #[Joining Date|long-ar|ar-digits]#"
  let tags = findTags(text)
  doAssert tags.len == 10
  doAssert tags[0].ask and tags[0].name == "Addressed to"
  doAssert tags[3].filters == @["n3"]
  let out1 = fillTags(text, values, answers)
  doAssert out1.startsWith("To Bank Muscat: Maryam Al Hinai of Sohar Hotel earns OMR 790.000 " &
                           "(Seven Hundred Ninety Omani Rials) since 2 September 2018 / 02/09/2018 " &
                           "#[Unknown]# سبعمائة وتسعون"), out1
  doAssert out1.endsWith("٢ سبتمبر ٢٠١٨"), out1
  doAssert fillTags("<b>#[Name]#</b>", {"name": "A & B"}.toTable, escape = true) == "<b>A &amp; B</b>"
  # broken or odd text stays text
  doAssert fillTags("#[ never closed", values) == "#[ never closed"
  doAssert fillTags("#[]# and ]# and #[", values) == "#[]# and ]# and #["
  doAssert tagKey("Total Salary") == tagKey("total_salary")
  doAssert tagKey("الراتب الإجمالي") == tagKey("الراتب  الإجمالي")

block vaultBlock:
  let t0 = cpuTime()
  let key = newVaultKey("4712")
  let secret = "{\"salary\": 790, \"name\": \"مريم\"}"
  let sealed = key.seal(secret)
  doAssert isSealed(sealed) and secret notin sealed
  doAssert key.seal(secret) != sealed, "a new nonce each time"
  doAssert key.unseal(sealed) == secret
  doAssert key.matches(sealed)
  let again = vaultKeyFor(sealed, "4712")
  doAssert again.unseal(sealed) == secret
  var wrong = false
  try: discard vaultKeyFor(sealed, "4713").unseal(sealed)
  except VaultError: wrong = true
  doAssert wrong, "a wrong password does not open it"
  var changed = sealed
  changed[^1] = char(ord(changed[^1]) xor 1)
  var caught = false
  try: discard key.unseal(changed)
  except VaultError: caught = true
  doAssert caught, "a changed byte is caught"
  var cut = false
  try: discard key.unseal(sealed[0 ..< sealed.len - 3])
  except VaultError: cut = true
  doAssert cut, "a cut file is caught"
  doAssert key.unseal(key.seal("")) == "", "empty text"
  echo "vault: three keys in ", formatFloat(cpuTime() - t0, ffDecimal, 2), " s"

echo "letters tests passed"
