## Deliverable 2 — Implementation handoff

**State:** discovery only; no code, issue, or production change was performed in this pass. [observed]

### Smallest-slice handoff

- **Module: evidence registry** — store Tier 1/Tier 2/Tier 3 sources with ids, urls, dates, and freshness fields. [inferred]  
- **Module: advice assembler** — combine matched claims, rank them, attach citations, and output a short answer with a confidence band. [inferred]  
- **Module: private constraint layer** — keep on-device user context for personalization only; no raw health data leaves the device unless explicitly needed and allowed. [inferred]  
- **Module: deterministic guardrails** — block diagnosis, medication, injury triage, and unsupported specificity. [inferred]  
- **Module: privacy filter** — redact raw health values from logs, traces, and analytics. [inferred]  

### Data model sketch

- **Source record:** `source_id, tier, title, canonical_url, author_or_org, published_at, accessed_at, freshness_days, provenance_note`. [inferred]  
- **Claim record:** `claim_id, source_ids[], summary, confidence_0_1, status, conflict_notes`. [inferred]  
- **User constraint record:** `constraint_key, value, local_only=true, last_updated_at`. [inferred]  
- **Advice response:** `answer_text, citations[], confidence_band, refusal_reason?`. [inferred]  

### Guardrail rules list

- Refuse diagnosis or medical advice. [inferred]  
- Refuse medication, supplementation safety, or injury triage guidance requiring clinical judgment. [inferred]  
- Refuse if evidence is stale, contradictory, or insufficient for the requested specificity. [inferred]  
- Keep scope to general training/nutrition advice, not a full workout or meal-plan generator. [inferred]  
- Suppress raw health values in logs and traces. [inferred]  

### Source ingestion approach

- Pull curated public URLs only. [inferred]  
- Assign source tier at ingestion. [inferred]  
- Extract publication date, author, and canonical URL. [inferred]  
- Mark any claim that lacks a Tier 3 anchor as provisional. [inferred]  

### Test checklist

- Unit: ranking, formatting, confidence bands, redaction. [inferred]  
- Guardrail: refusal on unsafe topics. [inferred]  
- Evidence registry: recency and conflict resolution. [inferred]  
- Privacy: no raw-health leakage to logs/analytics. [inferred]  
- End-to-end: narrow progress-check question returns cited answer or principled refusal. [inferred]  

### Launch-by-flag recommendation

- Ship behind a private feature flag for Tim-only dogfood, then widen only after review of trust, refusal quality, and privacy checks. [inferred]  
- Keep the canonical PR/CI path through JovieInc/LogYourBody standard PR + CI + release process if implementation is later approved. [inferred]  

---

## Compact end notes

**Full source list:**  
1. RP YouTube channel — https://www.youtube.com/@RenaissancePeriodization  
2. RP hypertrophy progression article — https://rpstrength.com/blogs/articles/progressing-for-hypertrophy  
3. RP hypertrophy guide hub — https://rpstrength.com/blogs/articles/complete-hypertrophy-training-guide  
4. Menno homepage — https://mennohenselmans.com/  
5. Menno optimal training volume — https://mennohenselmans.com/optimal-training-volume/  
6. Menno protein myth — https://mennohenselmans.com/the-myth-of-1glb-optimal-protein-intake-for-bodybuilders/  
7. Protein supplementation meta-analysis — https://pubmed.ncbi.nlm.nih.gov/28698222/  
8. ISSN protein position stand — https://jissn.biomedcentral.com/articles/10.1186/s12970-017-0177-8  
9. Protein intake/support muscle mass & function meta-analysis — https://pmc.ncbi.nlm.nih.gov/articles/PMC8978023/  
10. Low- vs high-load resistance training meta-analysis — https://pubmed.ncbi.nlm.nih.gov/28834797/  

**Rejected design alternatives:**  
- Pure open-ended chat advisor — too easy to hallucinate and too hard to guardrail.  
- Full meal/workout planner — out of LYB scope and increases safety/privacy risk.  
- Centralized learning from raw user health data — unnecessary for the slice and weak on privacy.  
- Single-source RP-only advice engine — practical but too fragile when evidence conflicts.  
- No-citation advice — faster, but destroys trust and makes uncertainty invisible.  

**Smallest-slice handoff summary:**  
A private, flag-gated “progress check advisor” that uses a tiered evidence registry, on-device user constraints, hard safety refusals, and cited confidence bands to answer one narrow gym-adjacent question with minimal data and no production mutation.
