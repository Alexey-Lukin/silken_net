# SPDX-License-Identifier: AGPL-3.0-or-later
# frozen_string_literal: true

# [UI.3] Один дім предиката «мітка звʼязана зі своїм полем» (WCAG 1.3.1).
#
# 🔴 Чому модуль, а не три копії в трьох спеках: копій я щойно й написав три, і
# всі знали ЛИШЕ явну асоціацію (`for` ⟷ `id`). HTML має ДВІ законні форми, і
# друга — мітка, що ОБГОРТАЄ контрол, — читалась би тими пінами як сирота.
# Живих вкладених міток у дереві сьогодні нуль, тож жоден приклад не червонів —
# рівно шаблон §Guard-craft #52: смуга зелена, дірка невидима, а перший, хто
# напише законну форму ПРАВИЛЬНО, дістане червоне на коректному коді. Найдешевша
# реакція на такий гейт — послабити його, тобто ціна over-broad вища за ціну
# пропуску.
#
# 🔒 Стеля названа, бо мовчання тут означало б «перевірено»:
#   · Предикат судить лише АСОЦІАЦІЮ. Порожня мітка, мітка з нечитабельним
#     текстом чи `aria-label`, що ПЕРЕКРИВАЄ вміст (див. скіл `frontend`), для
#     нього не існують.
#   · `aria-labelledby` як третя форма свідомо НЕ приймається: у дереві її нуль,
#     а мовчазне розширення переліку законних форм послаблює пін без сліду.
#     Зʼявиться сайт — додати сюди РАЗОМ із власною GREEN-пробою.
#   · Він не питає, чи мітка й контрол в одній формі: `for` через увесь документ
#     валідний за HTML і тут проходить.
module LabelAssociation
  module_function

  # → масив `<label>`-вузлів, НЕ звʼязаних із жодним контролом.
  # Порожній результат = всі мітки звʼязані.
  def orphan_labels(fragment)
    control_ids = fragment.css("input, select, textarea").filter_map { |n| n["id"] }

    fragment.css("label").reject do |label|
      explicit = label["for"].present? && control_ids.include?(label["for"])
      implicit = label.css("input, select, textarea").any?

      explicit || implicit
    end
  end

  # → масив id, на які показує `aria-describedby`, але яких у документі НЕМА.
  # Порожній результат = кожна підказка справді досяжна з поля.
  def dangling_descriptions(fragment)
    described = fragment.css("[aria-describedby]").flat_map { |n| n["aria-describedby"].split }
    present   = fragment.css("[id]").filter_map { |n| n["id"] }

    described.uniq - present
  end
end
