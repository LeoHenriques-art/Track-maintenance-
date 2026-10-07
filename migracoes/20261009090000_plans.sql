-- Planos do Facitrack: Essencial, Profissional e Empresa.
-- - Leituras do gerador e Contratos só existem no Profissional e no Empresa
--   (também nas regras da base de dados, não só no menu).
-- - Documentos lidos pela IA por mês: Essencial 300, Profissional 1000,
--   Empresa sem limite.
-- Só quem gere a plataforma muda o plano de uma empresa.
-- As empresas que já existem ficam no plano Empresa (tudo incluído).
-- Aplicar depois de 20261008090000_platform_admin.sql.

ALTER TABLE public.organizations
  ADD COLUMN IF NOT EXISTS plan TEXT NOT NULL DEFAULT 'empresa'
  CHECK (plan IN ('essencial', 'profissional', 'empresa'));

-- Novas empresas criadas pela plataforma começam no Essencial (pode mudar-se logo).
ALTER TABLE public.organizations ALTER COLUMN plan SET DEFAULT 'essencial';

-- Um administrador de empresa pode mudar o nome e as etiquetas, mas não o plano.
CREATE OR REPLACE FUNCTION public.protect_org_plan()
RETURNS TRIGGER LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
BEGIN
  IF NEW.plan IS DISTINCT FROM OLD.plan AND auth.uid() IS NOT NULL
     AND NOT public.is_platform_admin() THEN
    NEW.plan := OLD.plan;
  END IF;
  RETURN NEW;
END;
$$;
DROP TRIGGER IF EXISTS organizations_protect_plan ON public.organizations;
CREATE TRIGGER organizations_protect_plan BEFORE UPDATE ON public.organizations
  FOR EACH ROW EXECUTE FUNCTION public.protect_org_plan();

CREATE OR REPLACE FUNCTION public.org_has_feature(feature TEXT)
RETURNS BOOLEAN LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public AS $$
  SELECT CASE feature
    WHEN 'gerador' THEN o.plan IN ('profissional', 'empresa')
    WHEN 'contratos' THEN o.plan IN ('profissional', 'empresa')
    ELSE true
  END
  FROM public.organizations o WHERE o.id = public.current_org_id();
$$;
GRANT EXECUTE ON FUNCTION public.org_has_feature(TEXT) TO authenticated;

-- Regras das tabelas do gerador e dos contratos passam a exigir o plano.
DO $$
DECLARE
  t TEXT;
  f TEXT;
  s TEXT;
BEGIN
  FOR t, f, s IN VALUES
    ('fuel_readings', 'gerador', 'abastecimentos'),
    ('contracts', 'contratos', 'contratos'),
    ('contract_allocations', 'contratos', 'contratos')
  LOOP
    EXECUTE format('DROP POLICY IF EXISTS org_select ON public.%I', t);
    EXECUTE format('DROP POLICY IF EXISTS org_insert ON public.%I', t);
    EXECUTE format('DROP POLICY IF EXISTS org_update ON public.%I', t);
    EXECUTE format('DROP POLICY IF EXISTS org_delete ON public.%I', t);
    EXECUTE format('CREATE POLICY org_select ON public.%I FOR SELECT TO authenticated
      USING (organization_id = public.current_org_id() AND public.has_sector(%L) AND public.org_has_feature(%L))', t, s, f);
    EXECUTE format('CREATE POLICY org_insert ON public.%I FOR INSERT TO authenticated
      WITH CHECK (organization_id = public.current_org_id() AND public.can_write(%L) AND public.org_has_feature(%L))', t, s, f);
    EXECUTE format('CREATE POLICY org_update ON public.%I FOR UPDATE TO authenticated
      USING (organization_id = public.current_org_id() AND public.can_write(%L) AND public.org_has_feature(%L))
      WITH CHECK (organization_id = public.current_org_id() AND public.can_write(%L) AND public.org_has_feature(%L))', t, s, f, s, f);
    EXECUTE format('CREATE POLICY org_delete ON public.%I FOR DELETE TO authenticated
      USING (organization_id = public.current_org_id() AND public.can_delete(%L) AND public.org_has_feature(%L))', t, s, f);
  END LOOP;
END $$;

-- Documentos lidos pela IA (um registo por leitura bem-sucedida).
CREATE TABLE IF NOT EXISTS public.ai_usage (
  id BIGSERIAL PRIMARY KEY,
  organization_id UUID NOT NULL REFERENCES public.organizations(id) ON DELETE CASCADE,
  kind TEXT NOT NULL,
  created_by UUID,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS ai_usage_org_month_idx ON public.ai_usage (organization_id, created_at);
ALTER TABLE public.ai_usage ENABLE ROW LEVEL SECURITY;
-- Só se escreve através das funções abaixo; a leitura direta não é precisa.

CREATE OR REPLACE FUNCTION public.plan_ai_limit(p TEXT)
RETURNS INT LANGUAGE sql IMMUTABLE AS $$
  SELECT CASE p WHEN 'essencial' THEN 300 WHEN 'profissional' THEN 1000 ELSE NULL END;
$$;

-- Uso deste mês da empresa de quem pergunta: used, monthly_limit (NULL = sem limite), plan.
CREATE OR REPLACE FUNCTION public.ai_usage_this_month()
RETURNS TABLE (used BIGINT, monthly_limit INT, plan TEXT)
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public AS $$
  SELECT
    (SELECT count(*) FROM public.ai_usage u
      WHERE u.organization_id = o.id AND u.created_at >= date_trunc('month', now())),
    public.plan_ai_limit(o.plan),
    o.plan
  FROM public.organizations o WHERE o.id = public.current_org_id();
$$;
GRANT EXECUTE ON FUNCTION public.ai_usage_this_month() TO authenticated;

-- Antes de chamar a IA: falha com uma mensagem clara se o limite do mês acabou.
CREATE OR REPLACE FUNCTION public.ai_check_quota()
RETURNS VOID LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = public AS $$
DECLARE
  u BIGINT;
  l INT;
BEGIN
  SELECT used, monthly_limit INTO u, l FROM public.ai_usage_this_month();
  IF l IS NOT NULL AND u >= l THEN
    RAISE EXCEPTION 'A sua empresa já usou os % documentos lidos por IA incluídos no plano este mês. Pode continuar a registar à mão, ou pedir a mudança de plano.', l
      USING ERRCODE = 'P0001';
  END IF;
END;
$$;
GRANT EXECUTE ON FUNCTION public.ai_check_quota() TO authenticated;

-- Depois de uma leitura bem-sucedida.
CREATE OR REPLACE FUNCTION public.ai_record_usage(kind TEXT, documents INT DEFAULT 1)
RETURNS VOID LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  org UUID := public.current_org_id();
BEGIN
  IF org IS NULL THEN RETURN; END IF;
  INSERT INTO public.ai_usage (organization_id, kind, created_by)
  SELECT org, left(kind, 40), auth.uid() FROM generate_series(1, greatest(1, least(documents, 50)));
END;
$$;
GRANT EXECUTE ON FUNCTION public.ai_record_usage(TEXT, INT) TO authenticated;

-- Lista da plataforma com o plano e o uso de IA deste mês.
DROP FUNCTION IF EXISTS public.platform_organizations();
CREATE OR REPLACE FUNCTION public.platform_organizations()
RETURNS TABLE (
  id UUID,
  name TEXT,
  unit_label_plural TEXT,
  created_at TIMESTAMPTZ,
  members BIGINT,
  admins BIGINT,
  units BIGINT,
  pending_invites BIGINT,
  admin_invite TEXT,
  plan TEXT,
  ai_used BIGINT,
  ai_limit INT
)
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = public AS $$
BEGIN
  IF NOT public.is_platform_admin() THEN
    RAISE EXCEPTION 'Sem permissão.' USING ERRCODE = '42501';
  END IF;
  RETURN QUERY
  SELECT o.id, o.name, o.unit_label_plural, o.created_at,
    (SELECT count(*) FROM public.memberships m WHERE m.organization_id = o.id AND m.active),
    (SELECT count(*) FROM public.memberships m WHERE m.organization_id = o.id AND m.active AND m.role = 'admin'),
    (SELECT count(*) FROM public.agencies a WHERE a.organization_id = o.id),
    (SELECT count(*) FROM public.invitations i WHERE i.organization_id = o.id AND i.accepted_at IS NULL),
    (SELECT i.email FROM public.invitations i
      WHERE i.organization_id = o.id AND i.accepted_at IS NULL AND i.role = 'admin'
      ORDER BY i.created_at LIMIT 1),
    o.plan,
    (SELECT count(*) FROM public.ai_usage u
      WHERE u.organization_id = o.id AND u.created_at >= date_trunc('month', now())),
    public.plan_ai_limit(o.plan)
  FROM public.organizations o
  ORDER BY o.created_at;
END;
$$;
GRANT EXECUTE ON FUNCTION public.platform_organizations() TO authenticated;

CREATE OR REPLACE FUNCTION public.platform_set_plan(org UUID, new_plan TEXT)
RETURNS VOID LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
BEGIN
  IF NOT public.is_platform_admin() THEN
    RAISE EXCEPTION 'Sem permissão.' USING ERRCODE = '42501';
  END IF;
  IF new_plan NOT IN ('essencial', 'profissional', 'empresa') THEN
    RAISE EXCEPTION 'Plano desconhecido: %', new_plan;
  END IF;
  UPDATE public.organizations SET plan = new_plan WHERE id = org;
END;
$$;
GRANT EXECUTE ON FUNCTION public.platform_set_plan(UUID, TEXT) TO authenticated;
