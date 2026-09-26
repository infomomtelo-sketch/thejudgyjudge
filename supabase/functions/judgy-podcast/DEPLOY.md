# judgy-podcast — deploy (Supabase dashboard, project dmemzljerldzeiwqfxzp)

1. **Voices:** Judgy (`54Cze5LrTSyLgbO6Fhlc`) and Barry (`8ZYhGJrsDOe4C8yzEEhP`) are already set at the top of `index.ts`. The verdict is read in Judgy's voice. If you ever change them, edit only those constants and redeploy.

2. **SQL editor** → paste and run `supabase/sql/podcast_usage.sql`. This creates the `podcast_usage` table with RLS on and no policies, plus the `podcast_try_consume` function, which only `service_role` can execute.

3. **Edge Functions → Secrets.** Check that `ANTHROPIC_API_KEY` and `ELEVENLABS_API_KEY` exist, then add:
   - `PODCAST_IP_SALT` = a long random string (for example the output of `openssl rand -hex 32`). **Required**: without it the function returns 503.
   - Optional: `PODCAST_IP_DAILY_CAP` (default 5), `PODCAST_GLOBAL_DAILY_CAP` (default 200), `PODCAST_ENABLED` (`false` = off).

4. **Edge Functions → judgy-podcast → Code.** Replace everything with `index.ts` and deploy. Leave **Verify JWT off**.

5. **Smoke test** from a terminal. Each successful episode uses 1 of your 5 per-IP episodes for the day.

   ```sh
   U=https://dmemzljerldzeiwqfxzp.supabase.co/functions/v1/judgy-podcast
   curl -si -X POST $U -H 'Origin: https://thejudgy.com' -H 'Content-Type: application/json' -d '{"topic":"ab"}' | head -1          # 400
   curl -si -X POST $U -H 'Content-Type: application/json' -d '{"topic":"Money stress"}' | head -1                                  # 403 (no Origin)
   curl -s  -X POST $U -H 'Origin: https://thejudgy.com' -H 'Content-Type: application/json' -d '{"topic":"Money stress"}' | head -c 300   # script + audio_b64
   ```

6. **Kill switch:** set the secret `PODCAST_ENABLED=false`. If the function still answers normally a minute later, redeploy it so it picks up the new secret.

## Why JWT verification is off, and the alternative

The function is public on purpose: the browser calls it with no key. That is acceptable **only** because:
- topics are validated server-side before anything paid runs,
- every episode is counted against a per-IP daily cap and a global daily cap **before** Anthropic or ElevenLabs is called,
- scripts are capped at 10 lines of at most 220 characters, so there are at most 10 ElevenLabs calls and 2,200 characters per episode,
- only the thejudgy.com origins are allowed, and there is a kill switch.

The alternative is to turn Verify JWT **on** and have the browser send the public anon key (`Authorization: Bearer <anon key>` and `apikey: <anon key>`). The CORS headers already allow both. The anon key is public, so this only filters out callers that aren't using Supabase. The caps stay the real protection either way.

## Manual test checklist (after deploying)

**A. Supabase, SQL editor**
- [ ] `select * from podcast_usage;` → 0 rows.
- [ ] `select has_table_privilege('anon','public.podcast_usage','select');` → `false`.
- [ ] `select has_function_privilege('anon','public.podcast_try_consume(date,text,integer,integer)','execute');` → `false`.
- [ ] The three curl checks in step 5 → 400, then 403, then a JSON episode.

**B. On your phone (iPhone Safari first, then Android Chrome), at thejudgy.com**
- [ ] The bottom bar reads **Court · Show · More**, with no Voice tab. Open any page from More: the bar is still there and doesn't cover the last line of text.
- [ ] More → Privacy mentions **ElevenLabs** and "AI-generated voices". More → Barry's referrals has no "affiliate" claim, and each link opens a plain URL (no `?referral=`).
- [ ] Show → tap a topic chip → **Go to court**. You see "Judgy and Barry are arguing…" for roughly 10–40 s, then the player with **"AI-generated voices. Judgy and Barry are fictional characters…"** above it.
- [ ] Press play (iOS usually blocks autoplay). You should hear Judgy's voice and Barry's voice take turns, then the verdict. **The time shown should match the whole episode, and it should play to the end without stopping after the first line.** This is the one thing I couldn't test (no Safari/WebKit here).
- [ ] Share → the share text includes "(AI-generated voices)".
- [ ] Make a second episode: the first one's audio stops and the new one plays.
- [ ] From the same network, the 6th episode of the day shows "That's all the episodes for today. Court reconvenes tomorrow." Everyone on the same Wi-Fi shares one IP; switching to mobile data gives you a fresh 5.

**C. Supabase → Edge Functions → judgy-podcast → Logs**
- [ ] A successful episode writes **no** `[judgy-podcast]` lines. The function only logs failures.
- [ ] If audio is missing, the log line tells you why:
  - `tts_skipped reason=voice_ids_not_set` → paste the voice IDs.
  - `tts_failed status=401` → ElevenLabs key.
  - `status=422` → voice ID or model ID.
  - `status=429` → ElevenLabs quota.
- [ ] Other lines to recognise:
  - `anthropic_failed status=401` → key; `404` → model not available to the account.
  - `usage_store_failed reason=usage_store_status_404` → the SQL wasn't run.
  - `missing_PODCAST_IP_SALT` → the secret isn't set.
- [ ] No topic text and no IP address appear anywhere in the logs.
- [ ] `select day, key, count from podcast_usage order by day desc, key;` → the `global` count equals the number of episodes made today. Every other key is `ip:` followed by 64 hex characters.

**D. Kill switch**
- [ ] Set `PODCAST_ENABLED=false`. Go to court now shows "The Show is off the air right now. Back soon." and no new rows or counts appear. Remove the secret (or set it to `true`) to turn the Show back on.

**E. Next day**
- [ ] ElevenLabs usage should be about episodes × 2,200 characters or less. Anthropic usage should show only `claude-haiku-4-5-20251001`.
