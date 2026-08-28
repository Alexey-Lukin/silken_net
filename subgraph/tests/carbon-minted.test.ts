// SPDX-License-Identifier: AGPL-3.0-or-later
//
// [OPS.36] Перший тест-шар мапінгу. Доти `subgraph/` була ЄДИНОЮ поверхнею репо без
// тестів узагалі — при тому, що саме з неї ESG-покупець і зовнішній аудитор читають
// нашу емісію.
//
// 🔴 ЧОМУ САМЕ `handleCarbonMinted`, а не «якийсь handler для початку». Три критерії
// сходяться на ньому одному: він тримає 8 із 11 умовних операторів файлу (решта
// чотирьох мають по одному null-чеку); він ЄДИНИЙ, що КЛАСИФІКУЄ, тож його помилка це
// криве ЧИСЛО, а не кривий рядок; і `GROWTH` є **ВІДСУТНІСТЮ мітки**, а не власною
// міткою — на дроті її немає. Отже будь-яка помилка класифікації зсунута В БІК
// ВУГЛЕЦЕВОГО КЛЕЙМУ: завищує рівно те число, яке читає аудитор.
//
// 🔒 ЩО ЦЕЙ ФАЙЛ ПОКРИВАЄ ПОНАД наявні гейти — і чому це не дубль. Три статичні спеки
// вже стоять над цією текою, і кожна ЯВНО оголосила, що не обчислює:
//   · `mint_prefix_parity_spec` звіряє ЛІТЕРАЛИ префіксів і прямо виносить порядок
//     перевірок у `mintKindOf` за межі скоупу («стереже коментар у самому мапінгу»);
//   · `subgraph_entity_completeness_spec` судить ПРИСВОЄННЯ, ніколи ЗНАЧЕННЯ, і сама
//     називає спадкоємця: «дім семантики — тест-шар мапінгу, matchstick-as, OPS.36»;
//   · `graph build` судить ТИПИ — зняття присвоєння не-nullable поля дало EXIT 0.
// Тобто дефекти нижче проходять зелено крізь УСІ ТРИ: `.plus()`→`.minus()`, реверс двох
// `if`, `load`→`new`, зріз не тієї довжини. Тест-шар починається рівно там, де вони
// поставили свою стелю.
//
// 🔒 СТЕЛЯ ЦЬОГО ФАЙЛУ, названа, щоб зелене не читалось ширше: тут юніт-рівень мапінгу
// на МОКОВАНИХ подіях. Він не стверджує нічого про те, чи контракт справді емітує такі
// події, чи маніфест слухає потрібну адресу (сьогодні всі три dataSource стоять на
// `0x0…0` зі `startBlock: 0`), ані про поведінку graph-node. Перше — дім
// `subgraph_abi_parity_spec`, друге — відкрита нога OPS.36 про «читача власного
// мовчання».

import {
  assert,
  describe,
  test,
  clearStore,
  afterEach,
  newMockEvent
} from "matchstick-as/assembly/index";
import { Address, BigInt, Bytes, ethereum } from "@graphprotocol/graph-ts";
import { CarbonMinted } from "../generated/SilkenCarbonCoin/SilkenCarbonCoin";
import { handleCarbonMinted } from "../src/mapping";

const INVESTOR = "0x0000000000000000000000000000000000000a11";
const BARE_DID = "did:peaq:0xdeadbeef";

function createCarbonMintedEvent(amount: i32, treeDid: string): CarbonMinted {
  let event = changetype<CarbonMinted>(newMockEvent());
  event.parameters = new Array<ethereum.EventParam>();

  // Порядок ПОЗИЦІЙНИЙ — акцесори `generated/` читають `parameters[N]`, не за іменем.
  event.parameters.push(
    new ethereum.EventParam(
      "investor",
      ethereum.Value.fromAddress(Address.fromString(INVESTOR))
    )
  );
  event.parameters.push(
    new ethereum.EventParam(
      "amount",
      ethereum.Value.fromUnsignedBigInt(BigInt.fromI32(amount))
    )
  );
  event.parameters.push(
    new ethereum.EventParam(
      "treeDidHash",
      ethereum.Value.fromBytes(Bytes.fromUTF8("hash"))
    )
  );
  event.parameters.push(
    new ethereum.EventParam("treeDid", ethereum.Value.fromString(treeDid))
  );
  event.parameters.push(
    new ethereum.EventParam(
      "archiveRoot",
      ethereum.Value.fromBytes(Bytes.fromUTF8("root"))
    )
  );

  return event;
}

// `ProtocolFinancials` має РІВНО ОДИН рядок ("1"), тож без очищення другий тест
// успадкував би агрегат першого — і кожен наступний пін читався б як накопичення.
afterEach(() => {
  clearStore();
});

describe("handleCarbonMinted", () => {
  describe("класифікація природи емісії", () => {
    // Дискримінатор, який `mint_prefix_parity_spec` ЯВНО лишив непокритим: він звіряє
    // літерали префіксів, а не логіку, що їх уживає.
    test("голий DID → GROWTH (мітки на дроті НЕМАЄ)", () => {
      handleCarbonMinted(createCarbonMintedEvent(100, BARE_DID));

      assert.fieldEquals("ProtocolFinancials", "1", "totalMintedGrowth", "100");
      assert.fieldEquals("ProtocolFinancials", "1", "totalMintedInsurance", "0");
      assert.fieldEquals("ProtocolFinancials", "1", "totalMintedTax", "0");
    });

    test("префікс INS_ → INSURANCE", () => {
      handleCarbonMinted(createCarbonMintedEvent(100, "INS_" + BARE_DID));

      assert.fieldEquals("ProtocolFinancials", "1", "totalMintedInsurance", "100");
      assert.fieldEquals("ProtocolFinancials", "1", "totalMintedGrowth", "0");
    });

    test("префікс TAX_BATCH_ → TAX", () => {
      handleCarbonMinted(createCarbonMintedEvent(100, "TAX_BATCH_" + BARE_DID));

      assert.fieldEquals("ProtocolFinancials", "1", "totalMintedTax", "100");
      assert.fieldEquals("ProtocolFinancials", "1", "totalMintedGrowth", "0");
    });

    // Податковий запис несе identifier ПЕРШОЇ tx підбатча, а вона сама може бути
    // страховою — тобто `TAX_BATCH_INS_<did>` є ЗАКОННОЮ формою, і класифікувати її
    // треба як TAX.
    // ⚠️ Назва цього тесту спершу казала «порядок перевірок несучий» — і мутація це
    // СПРОСТУВАЛА: реверс двох `if` у `mintKindOf` лишив приклад зеленим, бо
    // `TAX_BATCH_INS_` не починається з `INS_`. Тобто приклад правдивий, а приписана
    // йому ПІДСТАВА була хибна; справжню гарантію (жоден префікс не є початком іншого)
    // тримає `mint_prefix_parity_spec`, а справжню чутливість до порядку — тест
    // `subjectDid` нижче. Лишаю запис, бо без нього наступний прохід перевиведе те саме.
    test("TAX_BATCH_INS_ класифікується як TAX (зовнішній префікс виграє)", () => {
      handleCarbonMinted(
        createCarbonMintedEvent(100, "TAX_BATCH_INS_" + BARE_DID)
      );

      assert.fieldEquals("ProtocolFinancials", "1", "totalMintedTax", "100");
      assert.fieldEquals("ProtocolFinancials", "1", "totalMintedInsurance", "0");
    });

    // Тест не «ловить баг» — він фіксує ЗСУВ У БІК КЛЕЙМУ як НАВМИСНИЙ. Якщо правила
    // колись зміняться, цей приклад змусить ухвалити рішення, а не проїхати мовчки.
    test("нерозпізнаний префікс падає в GROWTH — зсув у бік клейму НАВМИСНИЙ", () => {
      handleCarbonMinted(createCarbonMintedEvent(100, "REFUND_" + BARE_DID));

      assert.fieldEquals("ProtocolFinancials", "1", "totalMintedGrowth", "100");
    });
  });

  describe("похідні поля запису", () => {
    test("treeDid лишається RAW — схема оголошує його першоджерелом перевірки", () => {
      let did = "TAX_BATCH_INS_" + BARE_DID;
      let event = createCarbonMintedEvent(100, did);
      handleCarbonMinted(event);

      let id =
        event.transaction.hash.toHexString() + "-" + event.logIndex.toString();

      // Якби мапінг зрізав префікс і тут, зовнішня перевірка похідних `kind`/`subjectDid`
      // стала б НЕМОЖЛИВОЮ — а `completeness`-спека бачить лише, що поле присвоєне.
      assert.fieldEquals("CarbonMintEvent", id, "treeDid", did);
      assert.fieldEquals("CarbonMintEvent", id, "kind", "TAX");
    });

    // Єдине місце у файлі, де два `if` КОМПОЗУЮТЬ: зріз не тієї довжини дає синтаксично
    // здоровий, семантично неправильний DID — тобто помилку, яку жоден тип не зловить.
    test("subjectDid знімає ОБИДВА префікси послідовно", () => {
      let event = createCarbonMintedEvent(100, "TAX_BATCH_INS_" + BARE_DID);
      handleCarbonMinted(event);

      let id =
        event.transaction.hash.toHexString() + "-" + event.logIndex.toString();

      assert.fieldEquals("CarbonMintEvent", id, "subjectDid", BARE_DID);
    });
  });

  describe("агрегат ProtocolFinancials", () => {
    // Найдешевший і найтихіший кейс: `getProtocolFinancials` — гілка, спільна для
    // чотирьох із пʼяти handler'ів. Заміна `load` на `new` компілюється зелено,
    // проходить усі три статичні спеки й дає індекс, де КОЖНЕ число дорівнює останній
    // події. Це рівно клас «синтаксично здоровий нуль».
    test("друга подія ДОДАЄ, а не скидає (cold-start ⊥ накопичення)", () => {
      handleCarbonMinted(createCarbonMintedEvent(100, BARE_DID));
      handleCarbonMinted(createCarbonMintedEvent(50, BARE_DID));

      assert.fieldEquals("ProtocolFinancials", "1", "totalMinted", "150");
      assert.fieldEquals("ProtocolFinancials", "1", "totalMintedGrowth", "150");
    });

    // 🔴 Інваріант, оголошений ДВІЧІ ПРОЗОЮ (`schema.graphql` + `mapping.ts`) і жодного
    // разу машинно. Саме він тримає тотожність supply-боку з `totalBurned`.
    test("totalMinted == Σ трьох природ після подій усіх видів", () => {
      handleCarbonMinted(createCarbonMintedEvent(100, BARE_DID));
      handleCarbonMinted(createCarbonMintedEvent(20, "INS_" + BARE_DID));
      handleCarbonMinted(createCarbonMintedEvent(3, "TAX_BATCH_" + BARE_DID));

      assert.fieldEquals("ProtocolFinancials", "1", "totalMinted", "123");
      assert.fieldEquals("ProtocolFinancials", "1", "totalMintedGrowth", "100");
      assert.fieldEquals("ProtocolFinancials", "1", "totalMintedInsurance", "20");
      assert.fieldEquals("ProtocolFinancials", "1", "totalMintedTax", "3");
    });
  });
});
