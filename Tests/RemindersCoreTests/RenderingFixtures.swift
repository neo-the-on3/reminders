// Expected human-readable output for the sample data in TextRendererTests, rendered at 2026-10-23T10:00:00Z in UTC.
// Captured from the original TypeScript implementation so the Swift renderer stays byte-for-byte compatible.
// Do not edit by hand.

let renderingCases: [RenderingCase] = [
  RenderingCase(
    "lists", verbose: false, color: false,
    stdout:
      "Name       Count  Overdue\n─────────────────────────\nGroceries     12        0\nHome 🏠        3        2\nAd             0        0\n",
    stderr: ""),
  RenderingCase("listsEmpty", verbose: false, color: false, stdout: "No reminder lists found.\n", stderr: ""),
  RenderingCase(
    "remindersPlain", verbose: false, color: false,
    stdout:
      " ○ Buy milk today  !!!  ⚑  📝  [Dairy]\n ○ Pay rent 3d overdue  ↻ monthly  !!\n ✓ Call mum 1d overdue\n ○ Dentist tomorrow  ↻  !\n ○ Renew passport Nov 15\n ○ File taxes Apr 1 2027  [Money]\n ○ Read book 📝\n ○ Soon in 5d  [Dairy]\n\n",
    stderr: ""),
  RenderingCase(
    "remindersEmpty", verbose: false, color: false, stdout: "No reminders found in \"Groceries\".\n",
    stderr: ""),
  RenderingCase(
    "remindersList", verbose: false, color: false,
    stdout:
      "\nGroceries (8 reminders, 1 overdue)\n───────────\n\n Dairy\n ○ Buy milk today  !!!  ⚑  📝\n ○ Soon in 5d\n\n Money\n ○ File taxes Apr 1 2027\n\n Others\n ○ Pay rent 3d overdue  ↻ monthly  !!\n ✓ Call mum 1d overdue\n ○ Dentist tomorrow  ↻  !\n ○ Renew passport Nov 15\n ○ Read book 📝\n\n",
    stderr: ""),
  RenderingCase(
    "remindersToday", verbose: false, color: false,
    stdout:
      " ○ Pay rent ↻ monthly  !!  [Home]\n ✓ Call mum [Home]\n ○ Buy milk !!!  ⚑  📝  [Dairy]  [Groceries]\n ○ Dentist ↻  !  [Home]\n ○ Soon [Dairy]  [Admin]\n ○ Renew passport [Home]\n ○ File taxes [Money]  [Admin]\n ○ Read book 📝  [Admin]\n\n",
    stderr: ""),
  RenderingCase(
    "remindersOverdue", verbose: false, color: false,
    stdout:
      " ○ Buy milk today  !!!  ⚑  📝  [Dairy]  [Groceries]\n ○ Pay rent 3d overdue  ↻ monthly  !!  [Home]\n ✓ Call mum 1d overdue  [Home]\n ○ Dentist tomorrow  ↻  !  [Home]\n ○ Renew passport Nov 15  [Home]\n ○ File taxes Apr 1 2027  [Money]  [Admin]\n ○ Read book 📝  [Admin]\n ○ Soon in 5d  [Dairy]  [Admin]\n\n",
    stderr: ""),
  RenderingCase(
    "remindersSorted", verbose: false, color: false,
    stdout:
      "\nAll (8 reminders, 1 overdue)\n─────\n ○ Pay rent 3d overdue  ↻ monthly  !!\n ✓ Call mum 1d overdue\n ○ Buy milk today  !!!  ⚑  📝  [Dairy]\n ○ Dentist tomorrow  ↻  !\n ○ Soon in 5d  [Dairy]\n ○ Renew passport Nov 15\n ○ File taxes Apr 1 2027  [Money]\n ○ Read book 📝\n\n",
    stderr: ""),
  RenderingCase(
    "sections", verbose: false, color: false,
    stdout: "\nSections in \"Groceries\"\n───────────────────────\n • Dairy (3)\n • Produce\n\n", stderr: ""),
  RenderingCase(
    "sectionsEmpty", verbose: false, color: false, stdout: "No sections found in \"Groceries\".\n",
    stderr: ""),
  RenderingCase("message", verbose: false, color: false, stdout: "✓ Created reminder\n", stderr: ""),
  RenderingCase(
    "error", verbose: false, color: false, stdout: "",
    stderr: "Error: No list matching \"x\"\nSuggestion: Available lists:\n  - A\n  - B\n"),
  RenderingCase(
    "lists", verbose: false, color: true,
    stdout:
      "\u{1B}[1mName     \u{1B}[22m  \u{1B}[1mCount\u{1B}[22m  \u{1B}[1mOverdue\u{1B}[22m\n─────────────────────────\nGroceries     12  \u{1B}[2m      0\u{1B}[22m\nHome 🏠        3  \u{1B}[31m      2\u{1B}[39m\nAd             0  \u{1B}[2m      0\u{1B}[22m\n",
    stderr: ""),
  RenderingCase("listsEmpty", verbose: false, color: true, stdout: "No reminder lists found.\n", stderr: ""),
  RenderingCase(
    "remindersPlain", verbose: false, color: true,
    stdout:
      " \u{1B}[2m○\u{1B}[22m Buy milk \u{1B}[33mtoday\u{1B}[39m  \u{1B}[31m!!!\u{1B}[39m  \u{1B}[38;2;255;149;0m⚑\u{1B}[39m  \u{1B}[2m📝\u{1B}[22m  \u{1B}[36m[Dairy]\u{1B}[39m\n \u{1B}[2m○\u{1B}[22m Pay rent \u{1B}[31m3d overdue\u{1B}[39m  \u{1B}[34m↻ monthly\u{1B}[39m  \u{1B}[33m!!\u{1B}[39m\n \u{1B}[32m✓\u{1B}[39m \u{1B}[9m\u{1B}[2mCall mum\u{1B}[22m\u{1B}[29m \u{1B}[31m1d overdue\u{1B}[39m\n \u{1B}[2m○\u{1B}[22m Dentist \u{1B}[2mtomorrow\u{1B}[22m  \u{1B}[34m↻\u{1B}[39m  \u{1B}[34m!\u{1B}[39m\n \u{1B}[2m○\u{1B}[22m Renew passport \u{1B}[2mNov 15\u{1B}[22m\n \u{1B}[2m○\u{1B}[22m File taxes \u{1B}[2mApr 1 2027\u{1B}[22m  \u{1B}[36m[Money]\u{1B}[39m\n \u{1B}[2m○\u{1B}[22m Read book \u{1B}[2m📝\u{1B}[22m\n \u{1B}[2m○\u{1B}[22m Soon \u{1B}[2min 5d\u{1B}[22m  \u{1B}[36m[Dairy]\u{1B}[39m\n\n",
    stderr: ""),
  RenderingCase(
    "remindersEmpty", verbose: false, color: true, stdout: "No reminders found in \"Groceries\".\n",
    stderr: ""),
  RenderingCase(
    "remindersList", verbose: false, color: true,
    stdout:
      "\u{1B}[1m\u{1B}[22m\n\u{1B}[1mGroceries\u{1B}[22m\u{1B}[2m (8 reminders, \u{1B}[31m1 overdue\u{1B}[39m)\u{1B}[22m\n\u{1B}[2m\u{1B}[22m───────────\n\n \u{1B}[1m\u{1B}[4mDairy\u{1B}[24m\u{1B}[22m\n \u{1B}[2m○\u{1B}[22m Buy milk \u{1B}[33mtoday\u{1B}[39m  \u{1B}[31m!!!\u{1B}[39m  \u{1B}[38;2;255;149;0m⚑\u{1B}[39m  \u{1B}[2m📝\u{1B}[22m\n \u{1B}[2m○\u{1B}[22m Soon \u{1B}[2min 5d\u{1B}[22m\n\n \u{1B}[1m\u{1B}[4mMoney\u{1B}[24m\u{1B}[22m\n \u{1B}[2m○\u{1B}[22m File taxes \u{1B}[2mApr 1 2027\u{1B}[22m\n\n \u{1B}[2m\u{1B}[4mOthers\u{1B}[24m\u{1B}[22m\n \u{1B}[2m○\u{1B}[22m Pay rent \u{1B}[31m3d overdue\u{1B}[39m  \u{1B}[34m↻ monthly\u{1B}[39m  \u{1B}[33m!!\u{1B}[39m\n \u{1B}[32m✓\u{1B}[39m \u{1B}[9m\u{1B}[2mCall mum\u{1B}[22m\u{1B}[29m \u{1B}[31m1d overdue\u{1B}[39m\n \u{1B}[2m○\u{1B}[22m Dentist \u{1B}[2mtomorrow\u{1B}[22m  \u{1B}[34m↻\u{1B}[39m  \u{1B}[34m!\u{1B}[39m\n \u{1B}[2m○\u{1B}[22m Renew passport \u{1B}[2mNov 15\u{1B}[22m\n \u{1B}[2m○\u{1B}[22m Read book \u{1B}[2m📝\u{1B}[22m\n\n",
    stderr: ""),
  RenderingCase(
    "remindersToday", verbose: false, color: true,
    stdout:
      " \u{1B}[2m○\u{1B}[22m Pay rent \u{1B}[34m↻ monthly\u{1B}[39m  \u{1B}[33m!!\u{1B}[39m  \u{1B}[35m[Home]\u{1B}[39m\n \u{1B}[32m✓\u{1B}[39m \u{1B}[9m\u{1B}[2mCall mum\u{1B}[22m\u{1B}[29m \u{1B}[35m[Home]\u{1B}[39m\n \u{1B}[2m○\u{1B}[22m Buy milk \u{1B}[31m!!!\u{1B}[39m  \u{1B}[38;2;255;149;0m⚑\u{1B}[39m  \u{1B}[2m📝\u{1B}[22m  \u{1B}[36m[Dairy]\u{1B}[39m  \u{1B}[35m[Groceries]\u{1B}[39m\n \u{1B}[2m○\u{1B}[22m Dentist \u{1B}[34m↻\u{1B}[39m  \u{1B}[34m!\u{1B}[39m  \u{1B}[35m[Home]\u{1B}[39m\n \u{1B}[2m○\u{1B}[22m Soon \u{1B}[36m[Dairy]\u{1B}[39m  \u{1B}[35m[Admin]\u{1B}[39m\n \u{1B}[2m○\u{1B}[22m Renew passport \u{1B}[35m[Home]\u{1B}[39m\n \u{1B}[2m○\u{1B}[22m File taxes \u{1B}[36m[Money]\u{1B}[39m  \u{1B}[35m[Admin]\u{1B}[39m\n \u{1B}[2m○\u{1B}[22m Read book \u{1B}[2m📝\u{1B}[22m  \u{1B}[35m[Admin]\u{1B}[39m\n\n",
    stderr: ""),
  RenderingCase(
    "remindersOverdue", verbose: false, color: true,
    stdout:
      " \u{1B}[2m○\u{1B}[22m Buy milk \u{1B}[31mtoday\u{1B}[39m  \u{1B}[31m!!!\u{1B}[39m  \u{1B}[38;2;255;149;0m⚑\u{1B}[39m  \u{1B}[2m📝\u{1B}[22m  \u{1B}[36m[Dairy]\u{1B}[39m  \u{1B}[35m[Groceries]\u{1B}[39m\n \u{1B}[2m○\u{1B}[22m Pay rent \u{1B}[31m3d overdue\u{1B}[39m  \u{1B}[34m↻ monthly\u{1B}[39m  \u{1B}[33m!!\u{1B}[39m  \u{1B}[35m[Home]\u{1B}[39m\n \u{1B}[32m✓\u{1B}[39m \u{1B}[9m\u{1B}[2mCall mum\u{1B}[22m\u{1B}[29m \u{1B}[31m1d overdue\u{1B}[39m  \u{1B}[35m[Home]\u{1B}[39m\n \u{1B}[2m○\u{1B}[22m Dentist \u{1B}[31mtomorrow\u{1B}[39m  \u{1B}[34m↻\u{1B}[39m  \u{1B}[34m!\u{1B}[39m  \u{1B}[35m[Home]\u{1B}[39m\n \u{1B}[2m○\u{1B}[22m Renew passport \u{1B}[31mNov 15\u{1B}[39m  \u{1B}[35m[Home]\u{1B}[39m\n \u{1B}[2m○\u{1B}[22m File taxes \u{1B}[31mApr 1 2027\u{1B}[39m  \u{1B}[36m[Money]\u{1B}[39m  \u{1B}[35m[Admin]\u{1B}[39m\n \u{1B}[2m○\u{1B}[22m Read book \u{1B}[2m📝\u{1B}[22m  \u{1B}[35m[Admin]\u{1B}[39m\n \u{1B}[2m○\u{1B}[22m Soon \u{1B}[31min 5d\u{1B}[39m  \u{1B}[36m[Dairy]\u{1B}[39m  \u{1B}[35m[Admin]\u{1B}[39m\n\n",
    stderr: ""),
  RenderingCase(
    "remindersSorted", verbose: false, color: true,
    stdout:
      "\u{1B}[1m\u{1B}[22m\n\u{1B}[1mAll\u{1B}[22m\u{1B}[2m (8 reminders, \u{1B}[31m1 overdue\u{1B}[39m)\u{1B}[22m\n\u{1B}[2m\u{1B}[22m─────\n \u{1B}[2m○\u{1B}[22m Pay rent \u{1B}[31m3d overdue\u{1B}[39m  \u{1B}[34m↻ monthly\u{1B}[39m  \u{1B}[33m!!\u{1B}[39m\n \u{1B}[32m✓\u{1B}[39m \u{1B}[9m\u{1B}[2mCall mum\u{1B}[22m\u{1B}[29m \u{1B}[31m1d overdue\u{1B}[39m\n \u{1B}[2m○\u{1B}[22m Buy milk \u{1B}[33mtoday\u{1B}[39m  \u{1B}[31m!!!\u{1B}[39m  \u{1B}[38;2;255;149;0m⚑\u{1B}[39m  \u{1B}[2m📝\u{1B}[22m  \u{1B}[36m[Dairy]\u{1B}[39m\n \u{1B}[2m○\u{1B}[22m Dentist \u{1B}[2mtomorrow\u{1B}[22m  \u{1B}[34m↻\u{1B}[39m  \u{1B}[34m!\u{1B}[39m\n \u{1B}[2m○\u{1B}[22m Soon \u{1B}[2min 5d\u{1B}[22m  \u{1B}[36m[Dairy]\u{1B}[39m\n \u{1B}[2m○\u{1B}[22m Renew passport \u{1B}[2mNov 15\u{1B}[22m\n \u{1B}[2m○\u{1B}[22m File taxes \u{1B}[2mApr 1 2027\u{1B}[22m  \u{1B}[36m[Money]\u{1B}[39m\n \u{1B}[2m○\u{1B}[22m Read book \u{1B}[2m📝\u{1B}[22m\n\n",
    stderr: ""),
  RenderingCase(
    "sections", verbose: false, color: true,
    stdout:
      "\u{1B}[1m\u{1B}[22m\n\u{1B}[1mSections in \"Groceries\"\u{1B}[22m\n\u{1B}[1m\u{1B}[22m───────────────────────\n • Dairy\u{1B}[2m (3)\u{1B}[22m\n • Produce\n\n",
    stderr: ""),
  RenderingCase(
    "sectionsEmpty", verbose: false, color: true, stdout: "No sections found in \"Groceries\".\n",
    stderr: ""),
  RenderingCase(
    "message", verbose: false, color: true, stdout: "\u{1B}[32m✓\u{1B}[39m Created reminder\n", stderr: ""),
  RenderingCase(
    "error", verbose: false, color: true, stdout: "",
    stderr:
      "\u{1B}[31mError: No list matching \"x\"\u{1B}[39m\n\u{1B}[31m\u{1B}[39m\u{1B}[33mSuggestion: Available lists:\u{1B}[39m\n\u{1B}[33m  - A\u{1B}[39m\n\u{1B}[33m  - B\u{1B}[39m\n\u{1B}[33m\u{1B}[39m"
  ),
  RenderingCase(
    "lists", verbose: true, color: false,
    stdout:
      "Name       Count  Overdue\n─────────────────────────\nGroceries     12        0\nHome 🏠        3        2\nAd             0        0\n",
    stderr: ""),
  RenderingCase("listsEmpty", verbose: true, color: false, stdout: "No reminder lists found.\n", stderr: ""),
  RenderingCase(
    "remindersPlain", verbose: true, color: false,
    stdout:
      " ○ Buy milk today  !!!  ⚑  📝 Organic only, the big bottle from the shop round the corn...  [Dairy]\n ○ Pay rent 3d overdue  ↻ monthly  !!\n ✓ Call mum 1d overdue\n ○ Dentist tomorrow  ↻  !\n ○ Renew passport Nov 15\n ○ File taxes Apr 1 2027  [Money]\n ○ Read book 📝 Short note\n ○ Soon in 5d  [Dairy]\n\n",
    stderr: ""),
  RenderingCase(
    "remindersEmpty", verbose: true, color: false, stdout: "No reminders found in \"Groceries\".\n",
    stderr: ""),
  RenderingCase(
    "remindersList", verbose: true, color: false,
    stdout:
      "\nGroceries (8 reminders, 1 overdue)\n───────────\n\n Dairy\n ○ Buy milk today  !!!  ⚑  📝 Organic only, the big bottle from the shop round the corn...\n ○ Soon in 5d\n\n Money\n ○ File taxes Apr 1 2027\n\n Others\n ○ Pay rent 3d overdue  ↻ monthly  !!\n ✓ Call mum 1d overdue\n ○ Dentist tomorrow  ↻  !\n ○ Renew passport Nov 15\n ○ Read book 📝 Short note\n\n",
    stderr: ""),
  RenderingCase(
    "remindersToday", verbose: true, color: false,
    stdout:
      " ○ Pay rent ↻ monthly  !!  [Home]\n ✓ Call mum [Home]\n ○ Buy milk !!!  ⚑  📝 Organic only, the big bottle from the shop round the corn...  [Dairy]  [Groceries]\n ○ Dentist ↻  !  [Home]\n ○ Soon [Dairy]  [Admin]\n ○ Renew passport [Home]\n ○ File taxes [Money]  [Admin]\n ○ Read book 📝 Short note  [Admin]\n\n",
    stderr: ""),
  RenderingCase(
    "remindersOverdue", verbose: true, color: false,
    stdout:
      " ○ Buy milk today  !!!  ⚑  📝 Organic only, the big bottle from the shop round the corn...  [Dairy]  [Groceries]\n ○ Pay rent 3d overdue  ↻ monthly  !!  [Home]\n ✓ Call mum 1d overdue  [Home]\n ○ Dentist tomorrow  ↻  !  [Home]\n ○ Renew passport Nov 15  [Home]\n ○ File taxes Apr 1 2027  [Money]  [Admin]\n ○ Read book 📝 Short note  [Admin]\n ○ Soon in 5d  [Dairy]  [Admin]\n\n",
    stderr: ""),
  RenderingCase(
    "remindersSorted", verbose: true, color: false,
    stdout:
      "\nAll (8 reminders, 1 overdue)\n─────\n ○ Pay rent 3d overdue  ↻ monthly  !!\n ✓ Call mum 1d overdue\n ○ Buy milk today  !!!  ⚑  📝 Organic only, the big bottle from the shop round the corn...  [Dairy]\n ○ Dentist tomorrow  ↻  !\n ○ Soon in 5d  [Dairy]\n ○ Renew passport Nov 15\n ○ File taxes Apr 1 2027  [Money]\n ○ Read book 📝 Short note\n\n",
    stderr: ""),
  RenderingCase(
    "sections", verbose: true, color: false,
    stdout: "\nSections in \"Groceries\"\n───────────────────────\n • Dairy (3)\n • Produce\n\n", stderr: ""),
  RenderingCase(
    "sectionsEmpty", verbose: true, color: false, stdout: "No sections found in \"Groceries\".\n",
    stderr: ""),
  RenderingCase("message", verbose: true, color: false, stdout: "✓ Created reminder\n", stderr: ""),
  RenderingCase(
    "error", verbose: true, color: false, stdout: "",
    stderr: "Error: No list matching \"x\"\nSuggestion: Available lists:\n  - A\n  - B\n"),
  RenderingCase(
    "lists", verbose: true, color: true,
    stdout:
      "\u{1B}[1mName     \u{1B}[22m  \u{1B}[1mCount\u{1B}[22m  \u{1B}[1mOverdue\u{1B}[22m\n─────────────────────────\nGroceries     12  \u{1B}[2m      0\u{1B}[22m\nHome 🏠        3  \u{1B}[31m      2\u{1B}[39m\nAd             0  \u{1B}[2m      0\u{1B}[22m\n",
    stderr: ""),
  RenderingCase("listsEmpty", verbose: true, color: true, stdout: "No reminder lists found.\n", stderr: ""),
  RenderingCase(
    "remindersPlain", verbose: true, color: true,
    stdout:
      " \u{1B}[2m○\u{1B}[22m Buy milk \u{1B}[33mtoday\u{1B}[39m  \u{1B}[31m!!!\u{1B}[39m  \u{1B}[38;2;255;149;0m⚑\u{1B}[39m  \u{1B}[2m📝 Organic only, the big bottle from the shop round the corn...\u{1B}[22m  \u{1B}[36m[Dairy]\u{1B}[39m\n \u{1B}[2m○\u{1B}[22m Pay rent \u{1B}[31m3d overdue\u{1B}[39m  \u{1B}[34m↻ monthly\u{1B}[39m  \u{1B}[33m!!\u{1B}[39m\n \u{1B}[32m✓\u{1B}[39m \u{1B}[9m\u{1B}[2mCall mum\u{1B}[22m\u{1B}[29m \u{1B}[31m1d overdue\u{1B}[39m\n \u{1B}[2m○\u{1B}[22m Dentist \u{1B}[2mtomorrow\u{1B}[22m  \u{1B}[34m↻\u{1B}[39m  \u{1B}[34m!\u{1B}[39m\n \u{1B}[2m○\u{1B}[22m Renew passport \u{1B}[2mNov 15\u{1B}[22m\n \u{1B}[2m○\u{1B}[22m File taxes \u{1B}[2mApr 1 2027\u{1B}[22m  \u{1B}[36m[Money]\u{1B}[39m\n \u{1B}[2m○\u{1B}[22m Read book \u{1B}[2m📝 Short note\u{1B}[22m\n \u{1B}[2m○\u{1B}[22m Soon \u{1B}[2min 5d\u{1B}[22m  \u{1B}[36m[Dairy]\u{1B}[39m\n\n",
    stderr: ""),
  RenderingCase(
    "remindersEmpty", verbose: true, color: true, stdout: "No reminders found in \"Groceries\".\n",
    stderr: ""),
  RenderingCase(
    "remindersList", verbose: true, color: true,
    stdout:
      "\u{1B}[1m\u{1B}[22m\n\u{1B}[1mGroceries\u{1B}[22m\u{1B}[2m (8 reminders, \u{1B}[31m1 overdue\u{1B}[39m)\u{1B}[22m\n\u{1B}[2m\u{1B}[22m───────────\n\n \u{1B}[1m\u{1B}[4mDairy\u{1B}[24m\u{1B}[22m\n \u{1B}[2m○\u{1B}[22m Buy milk \u{1B}[33mtoday\u{1B}[39m  \u{1B}[31m!!!\u{1B}[39m  \u{1B}[38;2;255;149;0m⚑\u{1B}[39m  \u{1B}[2m📝 Organic only, the big bottle from the shop round the corn...\u{1B}[22m\n \u{1B}[2m○\u{1B}[22m Soon \u{1B}[2min 5d\u{1B}[22m\n\n \u{1B}[1m\u{1B}[4mMoney\u{1B}[24m\u{1B}[22m\n \u{1B}[2m○\u{1B}[22m File taxes \u{1B}[2mApr 1 2027\u{1B}[22m\n\n \u{1B}[2m\u{1B}[4mOthers\u{1B}[24m\u{1B}[22m\n \u{1B}[2m○\u{1B}[22m Pay rent \u{1B}[31m3d overdue\u{1B}[39m  \u{1B}[34m↻ monthly\u{1B}[39m  \u{1B}[33m!!\u{1B}[39m\n \u{1B}[32m✓\u{1B}[39m \u{1B}[9m\u{1B}[2mCall mum\u{1B}[22m\u{1B}[29m \u{1B}[31m1d overdue\u{1B}[39m\n \u{1B}[2m○\u{1B}[22m Dentist \u{1B}[2mtomorrow\u{1B}[22m  \u{1B}[34m↻\u{1B}[39m  \u{1B}[34m!\u{1B}[39m\n \u{1B}[2m○\u{1B}[22m Renew passport \u{1B}[2mNov 15\u{1B}[22m\n \u{1B}[2m○\u{1B}[22m Read book \u{1B}[2m📝 Short note\u{1B}[22m\n\n",
    stderr: ""),
  RenderingCase(
    "remindersToday", verbose: true, color: true,
    stdout:
      " \u{1B}[2m○\u{1B}[22m Pay rent \u{1B}[34m↻ monthly\u{1B}[39m  \u{1B}[33m!!\u{1B}[39m  \u{1B}[35m[Home]\u{1B}[39m\n \u{1B}[32m✓\u{1B}[39m \u{1B}[9m\u{1B}[2mCall mum\u{1B}[22m\u{1B}[29m \u{1B}[35m[Home]\u{1B}[39m\n \u{1B}[2m○\u{1B}[22m Buy milk \u{1B}[31m!!!\u{1B}[39m  \u{1B}[38;2;255;149;0m⚑\u{1B}[39m  \u{1B}[2m📝 Organic only, the big bottle from the shop round the corn...\u{1B}[22m  \u{1B}[36m[Dairy]\u{1B}[39m  \u{1B}[35m[Groceries]\u{1B}[39m\n \u{1B}[2m○\u{1B}[22m Dentist \u{1B}[34m↻\u{1B}[39m  \u{1B}[34m!\u{1B}[39m  \u{1B}[35m[Home]\u{1B}[39m\n \u{1B}[2m○\u{1B}[22m Soon \u{1B}[36m[Dairy]\u{1B}[39m  \u{1B}[35m[Admin]\u{1B}[39m\n \u{1B}[2m○\u{1B}[22m Renew passport \u{1B}[35m[Home]\u{1B}[39m\n \u{1B}[2m○\u{1B}[22m File taxes \u{1B}[36m[Money]\u{1B}[39m  \u{1B}[35m[Admin]\u{1B}[39m\n \u{1B}[2m○\u{1B}[22m Read book \u{1B}[2m📝 Short note\u{1B}[22m  \u{1B}[35m[Admin]\u{1B}[39m\n\n",
    stderr: ""),
  RenderingCase(
    "remindersOverdue", verbose: true, color: true,
    stdout:
      " \u{1B}[2m○\u{1B}[22m Buy milk \u{1B}[31mtoday\u{1B}[39m  \u{1B}[31m!!!\u{1B}[39m  \u{1B}[38;2;255;149;0m⚑\u{1B}[39m  \u{1B}[2m📝 Organic only, the big bottle from the shop round the corn...\u{1B}[22m  \u{1B}[36m[Dairy]\u{1B}[39m  \u{1B}[35m[Groceries]\u{1B}[39m\n \u{1B}[2m○\u{1B}[22m Pay rent \u{1B}[31m3d overdue\u{1B}[39m  \u{1B}[34m↻ monthly\u{1B}[39m  \u{1B}[33m!!\u{1B}[39m  \u{1B}[35m[Home]\u{1B}[39m\n \u{1B}[32m✓\u{1B}[39m \u{1B}[9m\u{1B}[2mCall mum\u{1B}[22m\u{1B}[29m \u{1B}[31m1d overdue\u{1B}[39m  \u{1B}[35m[Home]\u{1B}[39m\n \u{1B}[2m○\u{1B}[22m Dentist \u{1B}[31mtomorrow\u{1B}[39m  \u{1B}[34m↻\u{1B}[39m  \u{1B}[34m!\u{1B}[39m  \u{1B}[35m[Home]\u{1B}[39m\n \u{1B}[2m○\u{1B}[22m Renew passport \u{1B}[31mNov 15\u{1B}[39m  \u{1B}[35m[Home]\u{1B}[39m\n \u{1B}[2m○\u{1B}[22m File taxes \u{1B}[31mApr 1 2027\u{1B}[39m  \u{1B}[36m[Money]\u{1B}[39m  \u{1B}[35m[Admin]\u{1B}[39m\n \u{1B}[2m○\u{1B}[22m Read book \u{1B}[2m📝 Short note\u{1B}[22m  \u{1B}[35m[Admin]\u{1B}[39m\n \u{1B}[2m○\u{1B}[22m Soon \u{1B}[31min 5d\u{1B}[39m  \u{1B}[36m[Dairy]\u{1B}[39m  \u{1B}[35m[Admin]\u{1B}[39m\n\n",
    stderr: ""),
  RenderingCase(
    "remindersSorted", verbose: true, color: true,
    stdout:
      "\u{1B}[1m\u{1B}[22m\n\u{1B}[1mAll\u{1B}[22m\u{1B}[2m (8 reminders, \u{1B}[31m1 overdue\u{1B}[39m)\u{1B}[22m\n\u{1B}[2m\u{1B}[22m─────\n \u{1B}[2m○\u{1B}[22m Pay rent \u{1B}[31m3d overdue\u{1B}[39m  \u{1B}[34m↻ monthly\u{1B}[39m  \u{1B}[33m!!\u{1B}[39m\n \u{1B}[32m✓\u{1B}[39m \u{1B}[9m\u{1B}[2mCall mum\u{1B}[22m\u{1B}[29m \u{1B}[31m1d overdue\u{1B}[39m\n \u{1B}[2m○\u{1B}[22m Buy milk \u{1B}[33mtoday\u{1B}[39m  \u{1B}[31m!!!\u{1B}[39m  \u{1B}[38;2;255;149;0m⚑\u{1B}[39m  \u{1B}[2m📝 Organic only, the big bottle from the shop round the corn...\u{1B}[22m  \u{1B}[36m[Dairy]\u{1B}[39m\n \u{1B}[2m○\u{1B}[22m Dentist \u{1B}[2mtomorrow\u{1B}[22m  \u{1B}[34m↻\u{1B}[39m  \u{1B}[34m!\u{1B}[39m\n \u{1B}[2m○\u{1B}[22m Soon \u{1B}[2min 5d\u{1B}[22m  \u{1B}[36m[Dairy]\u{1B}[39m\n \u{1B}[2m○\u{1B}[22m Renew passport \u{1B}[2mNov 15\u{1B}[22m\n \u{1B}[2m○\u{1B}[22m File taxes \u{1B}[2mApr 1 2027\u{1B}[22m  \u{1B}[36m[Money]\u{1B}[39m\n \u{1B}[2m○\u{1B}[22m Read book \u{1B}[2m📝 Short note\u{1B}[22m\n\n",
    stderr: ""),
  RenderingCase(
    "sections", verbose: true, color: true,
    stdout:
      "\u{1B}[1m\u{1B}[22m\n\u{1B}[1mSections in \"Groceries\"\u{1B}[22m\n\u{1B}[1m\u{1B}[22m───────────────────────\n • Dairy\u{1B}[2m (3)\u{1B}[22m\n • Produce\n\n",
    stderr: ""),
  RenderingCase(
    "sectionsEmpty", verbose: true, color: true, stdout: "No sections found in \"Groceries\".\n",
    stderr: ""),
  RenderingCase(
    "message", verbose: true, color: true, stdout: "\u{1B}[32m✓\u{1B}[39m Created reminder\n", stderr: ""),
  RenderingCase(
    "error", verbose: true, color: true, stdout: "",
    stderr:
      "\u{1B}[31mError: No list matching \"x\"\u{1B}[39m\n\u{1B}[31m\u{1B}[39m\u{1B}[33mSuggestion: Available lists:\u{1B}[39m\n\u{1B}[33m  - A\u{1B}[39m\n\u{1B}[33m  - B\u{1B}[39m\n\u{1B}[33m\u{1B}[39m"
  ),
]
