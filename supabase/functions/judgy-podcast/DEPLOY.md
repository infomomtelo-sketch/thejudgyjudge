# judgy-podcast — deploy (Supabase dashboard, project dmemzljerldzeiwqfxzp)

1. **Before you replace anything, copy from the current dashboard code:**
   - Judgy's and Barry's ElevenLabs voice IDs, plus the verdict voice if it's different → paste into `JUDGY_VOICE_ID` / `BARRY_VOICE_ID` / `VERDICT_VOICE_ID` at the top of `index.ts`.
   - The ElevenLabs `model_id`, if it isn't `eleven_multilingual_v2` → `ELEVEN_MODEL_ID`.
   - The script prompt, if you prefer the old wording → `SHOW_PROMPT`. Keep the `[JUDGY]` / `[BARRY]` / `[VERDICT]` format.

   Until the voice IDs are pasted in, the function works but returns script-only episodes, and the log says `tts_skipped reason=voice_ids_not_set`.

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
