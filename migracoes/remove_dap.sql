-- Remove da plataforma a organização original (DAP) e TUDO o que lhe pertence:
-- agências, manutenções, limpezas, abastecimentos, leituras, fumigações,
-- incidentes, contratos, histórico, correções da IA, convites, fotografias dos
-- documentos e as contas das outras pessoas dessa organização.
-- A conta de quem gere a plataforma passa antes para a organização "Facitrack".
-- NÃO há forma de desfazer. Correr uma vez, no SQL Editor (Lovable Cloud).

DO $$
DECLARE
  dap UUID;
  home UUID;
  moved INT;
  removed_users INT;
  t TEXT;
BEGIN
  SELECT id INTO dap FROM public.organizations WHERE is_legacy AND name = 'DAP';
  IF dap IS NULL THEN
    RAISE NOTICE 'Não existe organização DAP: nada a apagar.';
    RETURN;
  END IF;
  IF NOT EXISTS (SELECT 1 FROM public.platform_admins) THEN
    RAISE EXCEPTION 'Nenhuma conta de administração da plataforma. Corra primeiro a migração 20261008090000_platform_admin.sql com o seu e-mail.';
  END IF;

  -- 1. Organização própria para quem gere a plataforma.
  SELECT id INTO home FROM public.organizations WHERE name = 'Facitrack';
  IF home IS NULL THEN
    INSERT INTO public.organizations (name, unit_label_singular, unit_label_plural, unit_label_feminine, plan)
    VALUES ('Facitrack', 'Instalação', 'Instalações', true, 'empresa')
    RETURNING id INTO home;
  END IF;
  UPDATE public.memberships
  SET organization_id = home, role = 'admin', sectors = '{}', active = true
  WHERE organization_id = dap AND user_id IN (SELECT user_id FROM public.platform_admins);
  GET DIAGNOSTICS moved = ROW_COUNT;

  -- Contas das outras pessoas da DAP (apagadas no passo 4).
  CREATE TEMP TABLE dap_people ON COMMIT DROP AS
    SELECT user_id FROM public.memberships WHERE organization_id = dap;

  -- 2. Fotografias e PDFs dos documentos. Se o Storage não deixar apagar por
  --    SQL, o resto continua e aparece um aviso para apagar as pastas à mão.
  BEGIN
    DELETE FROM storage.objects
    WHERE bucket_id = 'maintenance-docs'
      AND (name LIKE 'publico/%' OR name LIKE dap::TEXT || '/%');
  EXCEPTION WHEN others THEN
    RAISE NOTICE 'Ficheiros não apagados por SQL (%). Apague à mão, em Storage › maintenance-docs, a pasta "publico" e a pasta "%".', SQLERRM, dap;
  END;

  -- 3. Os dados, tabela a tabela (o histórico de cada linha apagada também sai
  --    no fim). Depois, a própria organização, com membros e convites.
  FOREACH t IN ARRAY ARRAY[
    'contract_allocations', 'contracts', 'fuel_readings', 'maintenance_labor',
    'maintenance_materials', 'maintenance_documents', 'extraction_corrections',
    'maintenances', 'maintenance_schedules', 'cleanings', 'cleaning_schedules',
    'supplies', 'supply_schedules', 'fumigations', 'incidents', 'agencies',
    'invitations', 'ai_usage'
  ] LOOP
    IF to_regclass('public.' || t) IS NOT NULL THEN
      EXECUTE format('DELETE FROM public.%I WHERE organization_id = $1', t) USING dap;
    END IF;
  END LOOP;
  DELETE FROM public.audit_log WHERE organization_id = dap;
  DELETE FROM public.organizations WHERE id = dap;

  -- 4. Contas das outras pessoas que só pertenciam à DAP.
  DELETE FROM auth.users
  WHERE id IN (SELECT user_id FROM dap_people)
    AND id NOT IN (SELECT user_id FROM public.platform_admins);
  GET DIAGNOSTICS removed_users = ROW_COUNT;

  RAISE NOTICE 'DAP removida. Contas movidas para "Facitrack": %. Outras contas apagadas: %.', moved, removed_users;
END $$;
