-- Administração da plataforma (Facitrack): quem a gere pode ver todas as
-- empresas clientes e criar uma nova empresa com o seu primeiro
-- administrador, sem SQL. Os dados de cada empresa continuam separados: estas
-- funções só devolvem totais, nunca registos de outra empresa.
-- Aplicar depois de 20260930090000_contracts.sql.

CREATE TABLE IF NOT EXISTS public.platform_admins (
  user_id UUID PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
ALTER TABLE public.platform_admins ENABLE ROW LEVEL SECURITY;
GRANT SELECT ON public.platform_admins TO authenticated;
DROP POLICY IF EXISTS platform_admins_self ON public.platform_admins;
CREATE POLICY platform_admins_self ON public.platform_admins FOR SELECT TO authenticated
  USING (user_id = auth.uid());

CREATE OR REPLACE FUNCTION public.is_platform_admin()
RETURNS BOOLEAN LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public AS $$
  SELECT EXISTS (SELECT 1 FROM public.platform_admins WHERE user_id = auth.uid());
$$;
GRANT EXECUTE ON FUNCTION public.is_platform_admin() TO authenticated;

-- O convite criado pela administração da plataforma fica na empresa nova, e
-- não na empresa de quem o cria.
CREATE OR REPLACE FUNCTION public.set_invitation_org()
RETURNS TRIGGER LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
BEGIN
  IF auth.uid() IS NOT NULL
     AND NOT (coalesce(current_setting('app.platform_invite', true), '') = 'on'
              AND public.is_platform_admin()) THEN
    NEW.organization_id := public.current_org_id();
  END IF;
  IF auth.uid() IS NOT NULL THEN
    NEW.invited_by := auth.uid();
  END IF;
  NEW.email := lower(trim(NEW.email));
  RETURN NEW;
END;
$$;

-- Lista das empresas, com totais (sem dados de cada empresa).
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
  admin_invite TEXT
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
      ORDER BY i.created_at LIMIT 1)
  FROM public.organizations o
  ORDER BY o.created_at;
END;
$$;
GRANT EXECUTE ON FUNCTION public.platform_organizations() TO authenticated;

-- Cria uma empresa e o convite do seu primeiro administrador.
CREATE OR REPLACE FUNCTION public.platform_create_organization(
  org_name TEXT,
  admin_email TEXT,
  unit_singular TEXT DEFAULT 'Agência',
  unit_plural TEXT DEFAULT 'Agências',
  unit_feminine BOOLEAN DEFAULT true
)
RETURNS UUID LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  org UUID;
  v_email TEXT := lower(trim(admin_email));
BEGIN
  IF NOT public.is_platform_admin() THEN
    RAISE EXCEPTION 'Sem permissão.' USING ERRCODE = '42501';
  END IF;
  IF coalesce(trim(org_name), '') = '' THEN
    RAISE EXCEPTION 'Indique o nome da empresa.';
  END IF;
  IF v_email !~ '^[^@\s]+@[^@\s]+\.[^@\s]+$' THEN
    RAISE EXCEPTION 'E-mail do administrador inválido.';
  END IF;
  IF EXISTS (SELECT 1 FROM public.memberships m JOIN auth.users u ON u.id = m.user_id
             WHERE lower(u.email) = v_email) THEN
    RAISE EXCEPTION 'O e-mail % já tem conta noutra empresa.', v_email;
  END IF;
  IF EXISTS (SELECT 1 FROM public.invitations WHERE lower(invitations.email) = v_email) THEN
    RAISE EXCEPTION 'Já existe um convite para %.', v_email;
  END IF;

  INSERT INTO public.organizations (name, unit_label_singular, unit_label_plural, unit_label_feminine)
  VALUES (trim(org_name), coalesce(nullif(trim(unit_singular), ''), 'Agência'),
          coalesce(nullif(trim(unit_plural), ''), 'Agências'), coalesce(unit_feminine, true))
  RETURNING id INTO org;

  PERFORM set_config('app.platform_invite', 'on', true);
  INSERT INTO public.invitations (organization_id, email, role, sectors)
  VALUES (org, v_email, 'admin', '{}');
  PERFORM set_config('app.platform_invite', '', true);

  RETURN org;
END;
$$;
GRANT EXECUTE ON FUNCTION public.platform_create_organization(TEXT, TEXT, TEXT, TEXT, BOOLEAN) TO authenticated;

-- Quem gere a plataforma. Troque o e-mail pelo da sua conta antes de correr;
-- pode acrescentar mais pessoas depois com a mesma linha.
INSERT INTO public.platform_admins (user_id)
SELECT id FROM auth.users WHERE lower(email) = lower('COLOQUE-AQUI-O-SEU-EMAIL')
ON CONFLICT DO NOTHING;
