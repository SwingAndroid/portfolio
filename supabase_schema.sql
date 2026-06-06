-- ─────────────────────────────────────────────────────────────────────────
-- Crypto Portfolio — Supabase Schema
-- Run this in: Supabase Dashboard → SQL Editor → New query → Run
-- ─────────────────────────────────────────────────────────────────────────

-- ── cryptos ───────────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS public.cryptos (
  id         UUID        PRIMARY KEY,
  user_id    UUID        NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  coin_id    TEXT        NOT NULL,
  name       TEXT        NOT NULL,
  symbol     TEXT        NOT NULL,
  image_url  TEXT,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  UNIQUE (user_id, coin_id)
);

ALTER TABLE public.cryptos ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Users manage their own cryptos"
  ON public.cryptos FOR ALL
  USING      (auth.uid() = user_id)
  WITH CHECK (auth.uid() = user_id);

-- ── transactions ──────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS public.transactions (
  id             UUID        PRIMARY KEY,
  user_id        UUID        NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  crypto_id      UUID        NOT NULL REFERENCES public.cryptos(id) ON DELETE CASCADE,
  type           TEXT        NOT NULL CHECK (type IN ('buy', 'sell')),
  quantity       NUMERIC     NOT NULL,
  price_per_coin NUMERIC     NOT NULL,
  date           TIMESTAMPTZ NOT NULL,
  note           TEXT,
  created_at     TIMESTAMPTZ NOT NULL DEFAULT now()
);

ALTER TABLE public.transactions ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Users manage their own transactions"
  ON public.transactions FOR ALL
  USING      (auth.uid() = user_id)
  WITH CHECK (auth.uid() = user_id);
