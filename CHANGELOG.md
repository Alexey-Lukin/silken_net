# Changelog

## [0.2.0](https://github.com/Alexey-Lukin/silken_net/compare/v0.1.0...v0.2.0) (2026-06-24)


### Features

* **anchor:** 3-spring Z-stack tolerance analysis (HW.8.7) ([0b32259](https://github.com/Alexey-Lukin/silken_net/commit/0b322594cc292994c2ab5c7ecd03b7118fd7c3f1))
* **cad:** §4.3 mechanical-lock barbs + DIN-471 groove (PicoGK) ([207d104](https://github.com/Alexey-Lukin/silken_net/commit/207d1040e4447f82067e1702617d4c18eeaaee85))
* **cad:** 5-SKU per-species sweep + cad_smoke.yml CI workflow ([e893bd3](https://github.com/Alexey-Lukin/silken_net/commit/e893bd34d617500097380a27f4a8594f3f239b18))
* **cad:** anchor v2 — graded gyroid anode (3 grading strategies) ([60723a8](https://github.com/Alexey-Lukin/silken_net/commit/60723a8c07317c7986366500c0eb7ac0dcbf4a26))
* **cad:** ARCH.25 two-phase connectivity + specific-surface validation ([a5ed3d9](https://github.com/Alexey-Lukin/silken_net/commit/a5ed3d97988a7d88e6bbb99bfbdef00df443259b))
* **cad:** Au-coated 7th coupon — DET-electrical ceiling (bracket pair to Ta) ([b68ccc1](https://github.com/Alexey-Lukin/silken_net/commit/b68ccc119d2ee8ea15353fdfc900ee83f5732afb))
* **cad:** capsule-end assembly + MATE-Ø audit (Деталь 3↔4, HW.17) ([0246930](https://github.com/Alexey-Lukin/silken_net/commit/02469300e86a9eaf53ec801dfcb3c035b0527c58))
* **cad:** cathode_flange draw + PicoGK render command + presentation gallery ([64dfaa6](https://github.com/Alexey-Lukin/silken_net/commit/64dfaa6bb47c5b694f09eaccb3da1fad3159db79))
* **cad:** CEM tolerances/notes PMI block (Noyron-native SSOT) ([4da6c57](https://github.com/Alexey-Lukin/silken_net/commit/4da6c5756e5014ffb383f67a0c1f219a413aac1b))
* **cad:** CEM-native engineering-drawing generator + Ti-coin PoC + research ([26c298e](https://github.com/Alexey-Lukin/silken_net/commit/26c298eb39431f2e02beb958d8dbbeea66b6cc0e))
* **cad:** DXF engineering-drawing export via netDxf ([f965b18](https://github.com/Alexey-Lukin/silken_net/commit/f965b18f0824fd104608de5546dbf899457885f4))
* **cad:** full bus-path through-rod in the axial stack + section reveal ([01ba714](https://github.com/Alexey-Lukin/silken_net/commit/01ba7141cdb0378b33c38f42432078206f65f74b))
* **cad:** monolithic bus model + F3 BusRodClears audit (HW.34, Tier-1) ([a2b3bb9](https://github.com/Alexey-Lukin/silken_net/commit/a2b3bb9b0a9994f1edd1ca17ccd0b0dc0da145ff))
* **cad:** monolithic bus rod render (BuildMonolithic) + CEM rollout (HW.34, Tier-2) ([871718c](https://github.com/Alexey-Lukin/silken_net/commit/871718cb92dc0d50cab2fb4cf3fa22e46541420b))
* **cad:** PicoGK Code-as-CAD subsystem — scaffold + Ti-coin + validation ([456d914](https://github.com/Alexey-Lukin/silken_net/commit/456d914583703d26c3f1572e41a4465f501c34c8))
* **cad:** real L-slot bayonet socket in the skirt candidate (interference 0) ([f3b8d97](https://github.com/Alexey-Lukin/silken_net/commit/f3b8d972772b4d2888bed74377b58defbebf352a))
* **cad:** section render command — cutaway reveal of the monolithic bus rod ([3a3a439](https://github.com/Alexey-Lukin/silken_net/commit/3a3a4392eec86e684824e0036ea00605305c7814))
* **cad:** ti_coin alloy-matrix bake-off — 6-alloy CEM family (Stage-2 down-select) ([f91ad4c](https://github.com/Alexey-Lukin/silken_net/commit/f91ad4c47c581a13b3d89af1c9169be2e00364f2))
* **cad:** Ti-coin Ø16 A_electrode gate + wallParam working-window scan ([0ca7eec](https://github.com/Alexey-Lukin/silken_net/commit/0ca7eec5f9484789b75d50fd8548541e0a3703bf))
* **cad:** Zone-1 gyroid anchor generator (v1, constant cartesian gyroid) ([781932a](https://github.com/Alexey-Lukin/silken_net/commit/781932a6b013c835b5bf81e02afcc0b3916e598c))
* **cad:** Zone-2 PEEK sleeve + full axial stack press-fit mate-audit ([273301a](https://github.com/Alexey-Lukin/silken_net/commit/273301acfd2d0a6ccf49fecde7dd2c2ee93468e6))
* **cad:** Деталь 3 Zone-3 cathode-flange generator (PicoGK, HW.17 phase 1) ([81fa952](https://github.com/Alexey-Lukin/silken_net/commit/81fa952e8e07e2c09a1df2815c945a91dd999202))
* **cad:** Деталь 4 PEEK radome v2c generator (PicoGK, HW.17 — anchor CAD family complete) ([5f9a877](https://github.com/Alexey-Lukin/silken_net/commit/5f9a877d0e1d63bed66198e388fc75d6aa16d046))
* **deploy:** declare missing deploy ENV + canopy DB isolation + CI POSTGRES_* [INF.12/B5] ([101792e](https://github.com/Alexey-Lukin/silken_net/commit/101792e8bd5e94ec934683125d2823cf82585dbb))
* **docs:** anchor-dimension drift guard + 01_01 §1 canonical-home (SSOT) ([2ea8d2f](https://github.com/Alexey-Lukin/silken_net/commit/2ea8d2f9be98afa33298bf8433a9a173c7aca587))
* **in_silico:** multi-alloy V/Al-release + Lamé comparative (Stage-2 coin bake-off) ([dabe69f](https://github.com/Alexey-Lukin/silken_net/commit/dabe69f6ca1f6847875d58edd78aec2b8f5ae7a2))
* **in_silico:** oxide-DET per-alloy — predicts Ta DET-risk pre-coin (WKB) ([d6a42b1](https://github.com/Alexey-Lukin/silken_net/commit/d6a42b1c0f692f7798ff7d582368b2bdfe8fec95))
* **in-silico:** anchor bus thermal-bridge calc → HW.34 (Cu bus dominates the PEEK break) ([e1b3f99](https://github.com/Alexey-Lukin/silken_net/commit/e1b3f996c986b67a5fdea638731eb35dc8c07a8c))
* **in-silico:** bus mechanical de-risk (script 55) + register anchor scripts 52-55 ([67e554e](https://github.com/Alexey-Lukin/silken_net/commit/67e554e47c584b7a82fd9ec0cc9769249c13c26f))
* **in-silico:** HW.3.IS frozen sync + contact-pressure bug-fix + H7/s6 ([58ed071](https://github.com/Alexey-Lukin/silken_net/commit/58ed07189c7bdead9062b5c32ec3e9d847d8a04c))
* **in-silico:** per-alloy monolithic-bus thermal — ties HW.34 ↔ HW.24 bake-off ([6248fcb](https://github.com/Alexey-Lukin/silken_net/commit/6248fcb56849287002c7d591655480f5c7422369))
* **in-silico:** unified thick-wall Lamé (HW.3.IS) + fix overstated thermal denominator at source ([b226ff3](https://github.com/Alexey-Lukin/silken_net/commit/b226ff3a1e11925cd23c4988b5cce02ea7e0c9cb))
* **observability:** mint attempt/success counters -&gt; Resilience SLO measurable ([41da1d5](https://github.com/Alexey-Lukin/silken_net/commit/41da1d512dac70250fac6101e408b5f07afedda7))
* **ops:** unauthenticated /ready readiness probe (DB + Redis) for orchestrators ([2af9ece](https://github.com/Alexey-Lukin/silken_net/commit/2af9ececcb836f426369140b3c0bdd20b947d217))
* **security:** boot-time Web3 network guard (testnet RPC + oracle key fail-closed) ([78122da](https://github.com/Alexey-Lukin/silken_net/commit/78122da18c54452dba8f92aca6ce070b94a5065a))
* **security:** Sentry scrubs secret values leaked into exception/message text ([a03794b](https://github.com/Alexey-Lukin/silken_net/commit/a03794bf4b00919f3e381f7575236a663e499973))
* **ssot:** thermal-stress One-Home drift guard ([c03a6e5](https://github.com/Alexey-Lukin/silken_net/commit/c03a6e522aea1f9f11d2ee336162b2b0754d0c54))


### Bug Fixes

* **06:** close CI Kamal secret-starvation + KREDIS/POSTGRES drift [B1/H2] ([c3ed301](https://github.com/Alexey-Lukin/silken_net/commit/c3ed30196fa090e1ccbc61b1e95e32dd1ad37152))
* **ci:** scope workflow token permissions + drop untrusted GHCR checkout ([1a34de4](https://github.com/Alexey-Lukin/silken_net/commit/1a34de449d82b862ef6fa9307fde825332130699))
* **deploy:** /ready probe also checks Kredis (Web3 lock Redis) [B8] ([09f5082](https://github.com/Alexey-Lukin/silken_net/commit/09f5082a148c07fb04203622a0525bdf41eeeb7f))
* **deploy:** close INF.13/INF.14 machine-half — runtime + observability config ([6c182ad](https://github.com/Alexey-Lukin/silken_net/commit/6c182ad800afbedc1b401a9dfb508bbf79cbb3a6))
* **deploy:** production multi-DB connection via POSTGRES_* components [B1/INF.16] ([f216c19](https://github.com/Alexey-Lukin/silken_net/commit/f216c19194051d7dd2886376e59df6c497e3c003))
* **deploy:** terraform apply-blockers + Kamal image path [INF.15] ([b3dab98](https://github.com/Alexey-Lukin/silken_net/commit/b3dab983650c08c9c745c8da4b8db3785194bc6a))
* **deploy:** WEB3_STRICT_MODE=true in deploy configs (INF.11 machine-half) ([e78ae22](https://github.com/Alexey-Lukin/silken_net/commit/e78ae22e9ac2b9e73b9fc4514e2d63dcfc97e167))
* **docs:** canonical WHO token (🤖+👤) for HW.33 meta-line (tracker:check) ([1b8ca6f](https://github.com/Alexey-Lukin/silken_net/commit/1b8ca6fae81142ec37c525e7262fcc558d8aedb2))
* **docs:** linkify bare 00_07 refs in 01_02 §6 (docs:check_refs) ([e07e745](https://github.com/Alexey-Lukin/silken_net/commit/e07e745e201e917fa915d1884af6d9cf53384802))
* **i18n:** correct "LorentzA" -&gt; "Lorenz" in contract metadata ([fe0b3ed](https://github.com/Alexey-Lukin/silken_net/commit/fe0b3ed19ede51c8361b3b3727975893297de0d3))
* **slashing:** add source-tree context to Field-Audit freeze alert (SLASH-1 review) ([a1383a0](https://github.com/Alexey-Lukin/silken_net/commit/a1383a022677dd4cf4654a37d121920c773e5103))
* **slashing:** positive-A-evidence gate (SLASH-1) — no burn without proven Category-A ([d298297](https://github.com/Alexey-Lukin/silken_net/commit/d2982970630b5641f061b59c4f5e21622bac5269))
* **telemetry:** TEST.2 — kill seed-dependent telemetry-spec flake (ENV-leak class) ([f237425](https://github.com/Alexey-Lukin/silken_net/commit/f2374259f5c6249166bfd1c3089e7da81641149a))

## Changelog

This file is maintained automatically by
[release-please](https://github.com/googleapis/release-please) from
[Conventional Commit](https://www.conventionalcommits.org) messages. Released
sections are generated — do not edit them by hand.
