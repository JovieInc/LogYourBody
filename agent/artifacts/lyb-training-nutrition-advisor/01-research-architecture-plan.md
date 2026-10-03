## Deliverable 1 — Cited research & architecture plan

### 1) Evidence registry design

**Claim C1.** The registry should use a three-tier source hierarchy: Tier 1 = practical/operational coaching sources, Tier 2 = evidence-based commentary that cites primary research, Tier 3 = primary literature and professional guidelines. [inferred]  
Sources: RP Strength YouTube channel overview and RP blog articles as practical sources; Menno Henselmans site and public articles as evidence-based commentary; PubMed/PMC and ISSN position stand as authority-tier sources. [https://www.youtube.com/@RenaissancePeriodization](https://www.youtube.com/@RenaissancePeriodization), [https://rpstrength.com/blogs/articles/progressing-for-hypertrophy](https://rpstrength.com/blogs/articles/progressing-for-hypertrophy), [https://mennohenselmans.com/optimal-training-volume/](https://mennohenselmans.com/optimal-training-volume/), [https://pubmed.ncbi.nlm.nih.gov/28698222/](https://pubmed.ncbi.nlm.nih.gov/28698222/), [https://jissn.biomedcentral.com/articles/10.1186/s12970-017-0177-8](https://jissn.biomedcentral.com/articles/10.1186/s12970-017-0177-8)  

**Claim C2.** RP Strength qualifies as the primary practical source because its YouTube channel is large, active, and explicitly presents RP as a bodybuilding/physique education brand with many training and nutrition videos. [observed]  
Source: RP YouTube channel overview. [https://www.youtube.com/@RenaissancePeriodization](https://www.youtube.com/@RenaissancePeriodization)  

**Claim C3.** Menno Henselmans qualifies as the secondary source because his public site explicitly frames its content as science-based physique coaching and includes articles that synthesize research into practical guidance. [observed]  
Sources: Menno homepage and article pages. [https://mennohenselmans.com/](https://mennohenselmans.com/), [https://mennohenselmans.com/optimal-training-volume/](https://mennohenselmans.com/optimal-training-volume/), [https://mennohenselmans.com/the-myth-of-1glb-optimal-protein-intake-for-bodybuilders/](https://mennohenselmans.com/the-myth-of-1glb-optimal-protein-intake-for-bodybuilders/)  

**Claim C4.** The tertiary tier should prefer systematic reviews, meta-analyses, and professional position stands because they aggregate multiple studies and are better suited for stable advice foundations than single studies. [inferred]  
Sources: PubMed meta-analysis and ISSN position stand. [https://pubmed.ncbi.nlm.nih.gov/28698222/](https://pubmed.ncbi.nlm.nih.gov/28698222/), [https://jissn.biomedcentral.com/articles/10.1186/s12970-017-0177-8](https://jissn.biomedcentral.com/articles/10.1186/s12970-017-0177-8)  

#### Source tiering schema

**Claim C5.** Each registry entry should store rank, recency window, provenance, and a conflict rule so the UI can prefer newer, higher-authority sources when advice disagrees. [inferred]  
Proposed schema:  
- **Rank:** T1 practical, T2 evidence-based commentary, T3 authority literature  
- **Recency window:** T1/T2 = 12–24 months preferred; T3 = 5–10 years preferred unless superseded  
- **Provenance:** channel/site/journal/organization, author identity, URL, publication date, last accessed date  
- **Conflict rule:** if T3 conflicts with T1/T2, T3 wins unless T3 is older and newer T1/T2 cite a newer high-quality review; in that case mark as “contested” rather than override. [inferred]  

#### Per-claim citation field format

**Claim C6.** A per-claim citation field should record source id, URL or canonical id, accessed date, confidence from 0–1, and freshness metadata so the UI can render provenance and uncertainty together. [inferred]  
Suggested format:  
`{ source_id, tier, url_or_id, published_at, accessed_at, confidence_0_1, freshness_days, note }`

#### Candidate source registry, minimum 8

**Claim C7.** RP Strength’s YouTube channel is a valid registry source because it is the brand’s canonical public video hub and contains numerous training and nutrition explainers. [observed]  
Source id: `T1-RP-YT-CHANNEL`  
URL: https://www.youtube.com/@RenaissancePeriodization  
Why: primary practical operational source.

**Claim C8.** RP’s “Progressing for Hypertrophy: Strategies for Optimal Muscle Growth” is a valid registry source because it is an official RP article on hypertrophy progression guidance. [observed]  
Source id: `T1-RP-HYPER-PROGRESSION`  
URL: https://rpstrength.com/blogs/articles/progressing-for-hypertrophy  
Why: practical article from the primary source.

**Claim C9.** RP’s hypertrophy guide/article hub is a valid registry source because it centralizes RP’s operational methodology on building muscle. [observed]  
Source id: `T1-RP-HYPER-GUIDE`  
URL: https://rpstrength.com/blogs/articles/complete-hypertrophy-training-guide  
Why: canonical practical guidance hub.

**Claim C10.** Menno Henselmans’ homepage is a valid registry source because it explicitly frames itself as “Science to Master your Physique,” signaling evidence-based public commentary. [observed]  
Source id: `T2-MH-HOME`  
URL: https://mennohenselmans.com/  
Why: secondary evidence-based commentary hub.

**Claim C11.** Menno Henselmans’ “New science on the optimal training volume” article is a valid registry source because it is a public synthesis of training-volume evidence. [observed]  
Source id: `T2-MH-VOLUME`  
URL: https://mennohenselmans.com/optimal-training-volume/  
Why: secondary source with explicit research synthesis.

**Claim C12.** Menno Henselmans’ “The myth of 1 g/lb: Optimal protein intake for bodybuilders” is a valid registry source because it directly discusses protein intake thresholds and cites meta-analytic work. [observed]  
Source id: `T2-MH-PROTEIN-MYTH`  
URL: https://mennohenselmans.com/the-myth-of-1glb-optimal-protein-intake-for-bodybuilders/  
Why: secondary source with explicit citations to primary research.

**Claim C13.** The protein supplementation meta-analysis in healthy adults is a valid authority-tier source because it is a peer-reviewed systematic review/meta-analysis accessible on PubMed/PMC. [observed]  
Source id: `T3-PROTEIN-META-2017`  
URL: https://pubmed.ncbi.nlm.nih.gov/28698222/  
Why: primary literature, quantitative synthesis.

**Claim C14.** The ISSN protein and exercise position stand is a valid authority-tier source because it is a professional consensus-style guideline in a sports nutrition journal. [observed]  
Source id: `T3-ISSN-PROTEIN-2017`  
URL: https://jissn.biomedcentral.com/articles/10.1186/s12970-017-0177-8  
Why: guideline/position stand.

**Claim C15.** The systematic review and meta-analysis on protein intake supporting muscle mass and function in healthy adults is a valid authority-tier source because it is a recent peer-reviewed synthesis on PubMed Central. [observed]  
Source id: `T3-PROTEIN-MASS-FUNCTION-2022`  
URL: https://pmc.ncbi.nlm.nih.gov/articles/PMC8978023/  
Why: recent authority-tier synthesis.

**Claim C16.** The low- vs high-load resistance training meta-analysis is a valid authority-tier source because it addresses a common hypertrophy programming tradeoff using systematic-review methods. [observed]  
Source id: `T3-LOAD-META-2017`  
URL: https://pubmed.ncbi.nlm.nih.gov/28834797/  
Why: primary literature on training modality effects.

#### Registry usage rule

**Claim C17.** For a user-facing advice claim, the registry should require at least one Tier 3 source or two independently aligned Tier 2 sources before the claim can be labeled “advice-ready.” [inferred]  
Reasoning: this reduces dependence on one coach’s opinion while preserving practical usefulness.

---

### 2) Feature architecture

#### Claim-citation & confidence pipeline

**Claim C18.** Advice should be assembled as a constrained synthesis pipeline: retrieve candidate claims from the registry, score by tier, recency, and agreement, then generate a short answer with citations and a confidence stamp. [inferred]  
Flow: evidence retrieval → claim matching → conflict resolution → confidence scoring → response drafting → UI rendering.

**Claim C19.** Confidence should be composed from source tier, agreement across sources, freshness, and user-context fit, then rounded into a simple UI band rather than exposed as a fake-precise number. [inferred]  
Suggested bands: low / medium / high, mapped from 0–1 internally.

#### Private user memory / constraint layer

**Claim C20.** The advice system should maintain a private, on-device constraint layer containing only user-owned context such as training history, preferences, equipment access, and prior adherence patterns. [inferred]  
Privacy-by-design rationale: the advice becomes personalized without centralizing raw health data.

**Claim C21.** The constraint layer should influence only ranking and framing, not override safety or evidence gates. [inferred]  
This prevents personalization from creating unsafe or unsupported recommendations.

#### Deterministic guardrail engine

**Claim C22.** A hard-rule engine should block medically risky topics, diagnosis, medication advice, eating-disorder content, and any recommendation that would require clinical judgment. [inferred]  
This is appropriate because the feature is advice, not medical care.

**Claim C23.** The guardrail layer should also block open-ended conversational drift into workout programming, supplement stacking, or nutrition plans when the evidence registry cannot support a specific answer. [inferred]  
This keeps the feature inside its intended scope and avoids hallucinated specificity.

#### Refusal / uncertainty policy

**Claim C24.** The system should refuse when evidence is absent, outdated, conflicting, or too user-specific, and should provide a short explanation plus a safe alternative such as “I can summarize what the evidence says generally.” [inferred]  

**Claim C25.** The UI should show calibrated uncertainty whenever the claim comes from mixed evidence or low freshness, rather than presenting a crisp answer that implies certainty. [inferred]  

#### Health-data privacy architecture

**Claim C26.** The advice feature should minimize data by storing only what is necessary for personalization, encrypt data at rest and in transit, and avoid training any model on raw user health data by default. [inferred]  

**Claim C27.** The system should never write raw health data into logs, analytics payloads, or prompt traces; any operational telemetry must be redacted or aggregated. [inferred]  

**Claim C28.** The privacy policy and in-product disclosures should explicitly state that user data remains user-owned and is used only to personalize advice inside the product boundary. [inferred]  

---

### 3) Options

#### 10x ambition vs 100x ambition

**Claim C29.** A 10x ambition is a full advisor that answers broad training and nutrition questions across phases, with personalized context and evidence citations. [inferred]  
Risk: high scope, high safety burden, more conflict resolution, more refusal cases.

**Claim C30.** A 100x ambition is an embedded coaching loop that learns from repeated logs, outcomes, and adherence signals to adjust advice continuously. [inferred]  
Risk: much higher privacy, safety, and validation burden; feasibility is materially lower without strong governance and robust longitudinal data.

#### Smallest vertical slice

**Claim C31.** The smallest genuinely useful slice is a “progress check advisor” that answers one narrow question: “Based on current logged trend and evidence registry, is the user’s recent training/nutrition setup broadly aligned with muscle-gain or fat-loss best practices?” [inferred]  
Why this slice: it is end-to-end, useful before/after a gym session, and can stay deterministic.

#### Full meaningful test coverage for that slice

**Claim C32.** Unit tests should cover claim ranking, citation formatting, confidence banding, and guardrail rule evaluation. [inferred]  
**Claim C33.** Evidence-registry tests should verify that Tier 3 sources outrank Tier 1/Tier 2 when conflicts exist and that stale claims lose freshness priority. [inferred]  
**Claim C34.** Privacy tests should verify redaction of raw values from logs and ensure no user-health payload reaches analytics or model-trace sinks. [inferred]  
**Claim C35.** Guardrail tests should confirm refusals for diagnosis, medication, injury triage, and unsafe specificity. [inferred]  

#### Metrics that prove value

**Claim C36.** The most relevant value metrics are answer acceptance rate, refusal appropriateness rate, citation trust clicks, user-reported clarity, and repeat use after a gym session. [inferred]  
These map directly to trust, comprehension, and repeat use.

#### Cheapest falsification test

**Claim C37.** The cheapest falsification test is a private prototype with 10–20 scripted gym-session prompts comparing the advice output against a human-reviewed reference answer set. [inferred]  
What would disprove it: if the prototype is often refused, feels non-actionable, or produces low-trust/conflicting answers even on narrow questions.

---
