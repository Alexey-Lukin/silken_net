# arXiv — прохання про endorsement для методичного пейпера

> **Що це:** текст листа до автора arXiv із проханням про endorsement у `cs.SE` і порядок дій навколо нього. Пейпер — [`agent_self_deception_taxonomy`](agent_self_deception_taxonomy.md).
> **Concern-шар, НЕ канон.** Правила arXiv тут переказано зі сторінок info.arxiv.org і блогу arXiv, прочитаних 2026-11-08; перед відправкою перечитай їх — політика змінювалась 2026-01-21.
> **Статус:** 🟡 чернетка; адресата не обрано, founder тексту ще не бачив — ⛔ до «так» не надсилати. **Дім стану:** [`00_07`](../../00_07_Action_Plan_Tracker.md) UNI.3 (нога «arXiv-подача»).

---

## 0. Що вимагає arXiv і що звідси випливає

- Новий автор без попередньої статті на arXiv у домені категорії отримує право подавати лише через **особистий endorsement** від усталеного автора arXiv того самого домену; інституційна пошта сама по собі більше не кваліфікує. Endorsement «is not peer review» — endorser засвідчує, що робота доречна для категорії.
- Endorsement оцінюють **по категорії**: основна — `cs.SE`; чи потрібен окремий для крос-листа `cs.AI`, первинка не каже — питати лише якщо arXiv попросить.
- **Порядок:** founder реєструється на arXiv і починає подання в `cs.SE` → arXiv надсилає лист із запитом на endorsement і кодом → цей код іде в лист нижче → endorser вводить його на arXiv. Без коду лист endorser-у марний, тож спершу подання, потім лист.
- **Кого просити:** автора, що вже публікувався в `cs.SE`; найприродніші — автори прецедентів, які пейпер сам цитує і з якими позиціюється (близнюк методу — `2606.14589`, `cs.SE` + `cs.AI`, тобто та сама пара категорій). Вибір адресата — founder-а; arXiv радить писати тому, хто знає предмет.

## Лист (EN)

**⬇️ КОПІЮВАТИ ВІД ЦЬОГО РЯДКА.** Усе вище — репо-шар, у лист він НЕ йде.

**Subject line:** arXiv endorsement request for cs.SE — a practitioner paper on self-applied failure taxonomies for coding agents

Dear [Name],

I am an independent software engineer, and this would be my first submission to arXiv. I am asking whether you would consider endorsing me for cs.SE.

The paper is "Counter-Rules and Carriers": a practitioner report on a failure taxonomy that a solo developer and an AI coding agent applied to their own work for several months. It proposes membership tests for nine classes of self-deception, compares counts of narrated rule firings and relapses across two measurement windows (a ratio, not a rate), and reports three negative results about measuring any of this from the agent's own records. [One sentence on why you: for example, that the paper cites your work as the closest prior work and positions itself against it.]

The full text is public in the project's repository: [link to the version being submitted].

I understand that endorsement is not peer review and only confirms that the paper is appropriate for the category. If you are willing, the endorsement code arXiv gave me is [code], and the form is at https://arxiv.org/auth/endorse. If you would rather not, or the paper does not fit cs.SE in your view, a short note saying so would help me just as much.

Thank you for considering it.

Kind regards,

`[sender's signature]`

**⬆️ КІНЕЦЬ ТЕКСТУ ЛИСТА.** Нижче знову репо-шар.

---

## 1. Перед «так»

- Посилання в листі має вести на версію, яку подаватимемо: після переписаних §4 і §8 — на коміт подання, а не на `main`.
- Перечитати `info.arxiv.org/help/endorsement.html` і адресу форми endorsement на день відправки.
- Код у лист вписує founder із листа arXiv; його в репо не кладемо.
