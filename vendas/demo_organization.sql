-- Organização de demonstração do Facitrack, só com dados fictícios.
-- Correr no SQL Editor (Lovable Cloud). Pode ser corrido outra vez: apaga os
-- dados da demonstração e recria-os com datas à volta do dia de hoje.
--
-- Antes de correr: troque o e-mail abaixo pelo da conta de demonstração.
-- Depois, em /login, escolha "Criar conta" com esse e-mail.

DO $$
DECLARE
  demo_email TEXT := 'COLOQUE-AQUI-O-EMAIL-DA-DEMO@exemplo.com';
  org UUID;
  ag UUID[];
  names TEXT[] := ARRAY['Maputo Baixa', 'Matola', 'Xai-Xai', 'Inhambane', 'Beira Centro', 'Chimoio',
                        'Tete', 'Quelimane', 'Nampula', 'Pemba', 'Lichinga', 'Nacala'];
  provinces TEXT[] := ARRAY['Maputo', 'Maputo', 'Gaza', 'Inhambane', 'Sofala', 'Manica',
                            'Tete', 'Zambézia', 'Nampula', 'Cabo Delgado', 'Niassa', 'Nampula'];
  companies TEXT[] := ARRAY['TecnoFrio Lda', 'ElectroSul', 'GeraMoz Serviços'];
  equipments TEXT[] := ARRAY['Ar condicionado', 'Gerador', 'UPS', 'Quadro elétrico'];
  c UUID;
  i INT;
  k INT;
  lvl NUMERIC;
  hrs NUMERIC;
  run NUMERIC;
  south BOOLEAN;
BEGIN
  IF demo_email LIKE 'COLOQUE-AQUI%' THEN
    RAISE EXCEPTION 'Troque o e-mail da conta de demonstração na linha demo_email.';
  END IF;

  SELECT id INTO org FROM public.organizations WHERE name = 'Facitrack Demo';
  IF org IS NULL THEN
    INSERT INTO public.organizations (name, unit_label_singular, unit_label_plural, unit_label_feminine)
    VALUES ('Facitrack Demo', 'Agência', 'Agências', true)
    RETURNING id INTO org;
  END IF;

  -- Recomeçar do zero (só os dados desta organização).
  DELETE FROM public.contract_allocations WHERE organization_id = org;
  DELETE FROM public.contracts WHERE organization_id = org;
  DELETE FROM public.fuel_readings WHERE organization_id = org;
  DELETE FROM public.maintenance_schedules WHERE organization_id = org;
  DELETE FROM public.cleaning_schedules WHERE organization_id = org;
  DELETE FROM public.supply_schedules WHERE organization_id = org;
  DELETE FROM public.maintenances WHERE organization_id = org;
  DELETE FROM public.cleanings WHERE organization_id = org;
  DELETE FROM public.supplies WHERE organization_id = org;
  DELETE FROM public.fumigations WHERE organization_id = org;
  DELETE FROM public.incidents WHERE organization_id = org;
  DELETE FROM public.agencies WHERE organization_id = org;

  -- Convite para a conta de demonstração (administrador, todos os setores).
  -- Por segurança, não se aceita um e-mail que já pertença a outra organização
  -- (por exemplo a sua conta principal): use um e-mail só para demonstrações.
  IF EXISTS (
    SELECT 1 FROM public.memberships m JOIN auth.users u ON u.id = m.user_id
    WHERE lower(u.email) = lower(demo_email) AND m.organization_id <> org
  ) THEN
    RAISE EXCEPTION 'O e-mail % já tem conta noutra organização. Use um e-mail só para a demonstração.', demo_email;
  END IF;
  DELETE FROM public.invitations WHERE lower(email) = lower(demo_email);
  INSERT INTO public.invitations (organization_id, email, role, sectors)
  VALUES (org, demo_email, 'admin', '{}');

  -- Agências.
  FOR i IN 1..12 LOOP
    INSERT INTO public.agencies (organization_id, code, name, province, generator_capacity, water_capacity)
    VALUES (org, (200 + i)::TEXT, 'Agência ' || names[i], provinces[i],
            CASE WHEN i IN (1, 5, 9) THEN '500' WHEN i = 11 THEN '250' ELSE '300' END, '5000')
    RETURNING id INTO c;
    ag := ag || c;
  END LOOP;

  -- Manutenções dos últimos 6 meses.
  FOR i IN 0..44 LOOP
    INSERT INTO public.maintenances (organization_id, agency_id, work_order_number, invoice_number,
      maintenance_type, status, client, company, equipment, equipment_code, service_date, price,
      has_signatures)
    VALUES (org, ag[(i % 12) + 1], 'OT-' || (2400 + i), 'FT-' || (800 + i),
      (CASE WHEN i % 4 = 0 THEN 'preventiva' WHEN i % 5 = 0 THEN 'emergencial' ELSE 'corretiva' END)::public.maintenance_type,
      'Concluída', 'Facitrack Demo', companies[(i % 3) + 1], equipments[(i % 4) + 1],
      upper(left(equipments[(i % 4) + 1], 2)) || '-' || (201 + (i % 12)),
      current_date - (5 + (i * 13) % 170), (4500 + (i * 3719) % 38000)::TEXT, true);
  END LOOP;
  -- Ar condicionado da Beira: avaria repetida, sempre pela mesma empresa.
  FOREACH k IN ARRAY ARRAY[12, 31, 48, 66] LOOP
    INSERT INTO public.maintenances (organization_id, agency_id, work_order_number, maintenance_type,
      status, company, equipment, equipment_code, service_date, price, has_signatures)
    VALUES (org, ag[5], 'OT-' || (3000 + k), 'corretiva', 'Concluída', 'TecnoFrio Lda',
      'Ar condicionado', 'AR-205', current_date - k, (16000 + k * 150)::TEXT, true);
  END LOOP;

  -- Limpezas, abastecimentos, fumigações e incidentes.
  FOR i IN 1..12 LOOP
    south := provinces[i] IN ('Maputo', 'Gaza', 'Inhambane');
    FOR k IN 0..4 LOOP
      INSERT INTO public.cleanings (organization_id, agency_id, cleaning_date, supplier, area, cost)
      VALUES (org, ag[i], current_date - (10 + k * 30),
              CASE WHEN south THEN 'LimpaMax' ELSE 'ServiLimpa' END, 'Geral',
              (12000 + (i % 4) * 1500)::TEXT);
    END LOOP;
    FOR k IN 0..3 LOOP
      INSERT INTO public.supplies (organization_id, agency_id, type, supplier, supply_date,
        quantity_liters, unit_price, total_price, generator_hours_before, generator_hours_after)
      VALUES (org, ag[i], 'combustivel', CASE WHEN i % 2 = 0 THEN 'PetroSul' ELSE 'CombusMoz' END,
        current_date - (20 + k * 38 + i), (150 + (i * 37 + k * 53) % 180)::TEXT,
        (CASE WHEN i = 8 AND k = 1 THEN 118 ELSE 87 + (i + k) % 4 END)::TEXT,
        ((150 + (i * 37 + k * 53) % 180) * (CASE WHEN i = 8 AND k = 1 THEN 118 ELSE 87 + (i + k) % 4 END))::TEXT,
        (4000 + k * 60 + i * 10)::TEXT, (4000 + k * 60 + i * 10)::TEXT);
      INSERT INTO public.supplies (organization_id, agency_id, type, supplier, supply_date,
        quantity_liters, total_price)
      VALUES (org, ag[i], 'agua', 'AquaLog', current_date - (15 + k * 40 + i), '5000',
        (3500 + (i % 3) * 400)::TEXT);
    END LOOP;
    INSERT INTO public.fumigations (organization_id, agency_id, fumigation_date, supplier, area, cost, next_date)
    VALUES (org, ag[i], current_date - (95 + i), 'FumiPro', 'Geral', '8500',
            CASE WHEN i IN (3, 10) THEN current_date - 4 ELSE current_date + (85 - i) END);
    IF i % 3 = 1 THEN
      INSERT INTO public.incidents (organization_id, agency_id, incident_date, incident_type, severity,
        status, description, cost)
      VALUES (org, ag[i], current_date - (20 + i), 'Inundação', 'Média',
              CASE WHEN i = 1 THEN 'Em resolução' ELSE 'Resolvido' END,
              'Infiltração no teto da sala de atendimento', '15000');
    END IF;
  END LOOP;

  -- Agendamentos (alguns em atraso, para aparecerem nos alertas).
  INSERT INTO public.maintenance_schedules (organization_id, agency_id, equipment, maintenance_type, scheduled_date)
  VALUES (org, ag[7], 'Gerador', 'preventiva', current_date - 6),
         (org, ag[2], 'Ar condicionado', 'preventiva', current_date + 10);
  INSERT INTO public.cleaning_schedules (organization_id, agency_id, area, scheduled_date)
  VALUES (org, ag[9], 'Geral', current_date - 3);
  INSERT INTO public.supply_schedules (organization_id, agency_id, type, scheduled_date)
  VALUES (org, ag[11], 'combustivel', current_date - 2);

  -- Leituras do gerador: 8 dias por agência.
  FOR i IN 1..12 LOOP
    lvl := 96 - i * 2;
    hrs := 4700 + i * 25;
    FOR k IN REVERSE 7..0 LOOP
      run := 2 + (i % 3);
      IF k < 7 THEN
        IF i = 5 AND k = 0 THEN
          lvl := lvl - 22;            -- Beira: combustível desce com o gerador parado
          run := 0;
        ELSIF i = 8 AND k = 0 THEN
          lvl := lvl - run * 3.5;     -- Quelimane: consumo muito acima do habitual
        ELSE
          lvl := lvl - run * 1.1;
        END IF;
        hrs := hrs + run;
      END IF;
      IF i = 11 THEN lvl := least(lvl, 24 - (7 - k)); END IF;   -- Lichinga: nível baixo
      INSERT INTO public.fuel_readings (organization_id, agency_id, reading_date, level_percent,
        has_reserve, reserve_liters, hour_meter, source)
      VALUES (org, ag[i], current_date - k, greatest(3, round(lvl)), i % 4 = 0,
              CASE WHEN i % 4 = 0 THEN 40 ELSE 0 END, round(hrs, 1), 'ia');
    END LOOP;
  END LOOP;

  -- Contratos e distribuição pelos centros de custo.
  INSERT INTO public.contracts (organization_id, department, service, supplier, periodicity,
    installment_value, end_date, status, sector, notes)
  VALUES
    (org, 'Operações', 'Limpeza', 'LimpaMax', 'Mensal', 620000, current_date + 45, 'Activo', 'limpezas', NULL),
    (org, 'Operações', 'Limpeza', 'ServiLimpa', 'Mensal', 410000, NULL, 'Activo', 'limpezas', NULL),
    (org, 'Operações', 'Fumigação', 'FumiPro', 'Bimestral', 96000, current_date + 180, 'Activo', 'fumigacoes', NULL),
    (org, 'Operações', 'Manutenção AVAC e Gerador', 'TecnoFrio Lda', 'Mensal', 280000, current_date + 20, 'Activo', 'manutencoes',
     'A confirmar: no mapa da manutenção a periodicidade estava “Quadrimestral”, mas na folha Registos é Mensal. Qual é a certa?'),
    (org, 'Operações', 'Manutenção Posto de Transformação', 'ElectroSul', 'Anual', 850000, current_date + 270, 'Activo', 'manutencoes', NULL),
    (org, 'Administrativo', 'Segurança', 'Guarda Total', 'Mensal', 1250000, current_date + 120, 'Activo', NULL, NULL),
    (org, 'Administrativo', 'Comunicações', 'NetMoz', 'Mensal', 310000, current_date + 400, 'Activo', NULL, NULL),
    (org, 'Administrativo', 'Combustível frota', 'PetroSul', 'Mensal', 1800000, NULL, 'Activo', 'abastecimentos', NULL);

  -- Os quatro contratos de operações ficam distribuídos pelas 12 agências e pela sede;
  -- o da ServiLimpa fica com 38 000 MZN por distribuir, para a demonstração.
  FOR c, k IN
    SELECT id, CASE WHEN supplier = 'ServiLimpa' THEN 38000 ELSE 0 END
    FROM public.contracts
    WHERE organization_id = org AND department = 'Operações' AND supplier <> 'ElectroSul'
  LOOP
    INSERT INTO public.contract_allocations (organization_id, contract_id, cost_center, agency_id, amount)
    SELECT org, c, x.center, x.agency, round((ct.installment_value - k) / 13, 2)
    FROM public.contracts ct,
         (SELECT '100 - Sede'::TEXT AS center, NULL::UUID AS agency
          UNION ALL
          SELECT a.code || ' - ' || a.name, a.id FROM public.agencies a WHERE a.organization_id = org) x
    WHERE ct.id = c;
  END LOOP;

  -- O histórico da demonstração começa limpo (sem as linhas criadas por este script).
  DELETE FROM public.audit_log WHERE organization_id = org AND changed_by IS NULL;

  RAISE NOTICE 'Organização de demonstração pronta: %', org;
END $$;
