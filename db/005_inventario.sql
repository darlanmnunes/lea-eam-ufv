-- 005: inventário completo da sala 108 e marcação de empréstimo.
-- Para o banco que já recebeu 001 a 004 (instalações novas já trazem tudo em 001 a 003).
-- Preserva os usos em aula e as datas dos semestres; recria só as unidades.
-- As unidades abaixo têm identificações de exemplo (EX-001...). O inventário real, com patrimônio e
-- série, fica fora do git, em db/privado/003_acervo_real.sql: não rode este arquivo no banco em uso.

alter table modelos add column if not exists emprestavel boolean not null default true;
alter table unidades drop constraint if exists unidades_modelo_id_numero_serie_key;

do $$ begin
  if exists (select 1 from emprestimo_itens) then
    raise exception 'Já há pedidos ligados às unidades: esta troca precisa de uma migração própria';
  end if;
end $$;

insert into categorias (id, nome, sigla, ordem) values
  ('estacao-total', 'Estações totais', 'ET', 1),
  ('gnss', 'Receptores GNSS e RTK', 'GN', 2),
  ('nivel', 'Níveis', 'NV', 3),
  ('teodolito', 'Teodolitos', 'TD', 4),
  ('laser-scanner', 'Laser scanner', 'LS', 5),
  ('aeronave', 'Drones e VANT', 'VT', 6),
  ('medicao', 'Bússolas e instrumentos de medição', 'MD', 7),
  ('acessorio', 'Miras, tripés e acessórios', 'AC', 8),
  ('desenho', 'Planímetros e desenho', 'DS', 9),
  ('apoio', 'Apoio de campo', 'AP', 10)
on conflict (id) do update set nome = excluded.nome, sigla = excluded.sigla, ordem = excluded.ordem;

insert into modelos (id, categoria_id, marca, nome, descricao, foto, emprestavel, ordem) values
  ('geodetic-gd2i', 'estacao-total', 'Geodetic', 'GD2i', 'Estação total das aulas práticas de Topografia. É o modelo com mais unidades no laboratório.', 'geodetic-gd2i.webp', true, 1),
  ('geodetic-gt2-plus', 'estacao-total', 'Geodetic', 'GT2+', 'Estação total para levantamento planialtimétrico e locação.', 'geodetic-gt2-plus.webp', true, 2),
  ('geodetic-gd8i', 'estacao-total', 'Geodetic', 'GD8i', 'Estação total para levantamento planialtimétrico e locação.', 'geodetic-gd8i.webp', true, 3),
  ('topcon-es-65', 'estacao-total', 'Topcon', 'ES-65', 'Estação total para levantamento planialtimétrico e locação.', 'topcon-es-65.webp', true, 4),
  ('topcon-gts-102n', 'estacao-total', 'Topcon', 'GTS-102N', 'Estação total para levantamento planialtimétrico e locação.', 'topcon-102n.webp', true, 5),
  ('topcon-gts-212', 'estacao-total', 'Topcon', 'GTS-212', 'Estação total para levantamento planialtimétrico e locação.', 'topcon-212.webp', true, 6),
  ('estacao-total-pentax', 'estacao-total', 'Estação total', 'Pentax', 'Estação total, precisão linear 2 mm + 2 ppm, alcance 3.500 m com 1 prisma e 250 m sem prisma, tempo medição 1 s, uso topografia, ac. 2 prismas alvos, 2 bastões 3,60 m, nível esférico, tripé ext. em alumínio, cabo transm.', null, true, 7),
  ('chc-i50', 'gnss', 'CHC Nav', 'i50', 'Receptor GNSS para posicionamento RTK.', 'chc-nav-i50.webp', true, 8),
  ('topomap-t10', 'gnss', 'Topomap', 'T10', 'Receptor GNSS para posicionamento RTK, usado em par como base e rover.', 'rtk-topomap-t10.webp', true, 9),
  ('emlid-reach-rs2', 'gnss', 'Emlid', 'Reach RS2', 'Receptor GNSS multifrequência para posicionamento RTK.', 'emild-reach-rs2.webp', true, 10),
  ('emlid-reach-rs2-plus', 'gnss', 'Emlid', 'Reach RS2+', 'Receptor GNSS multifrequência para posicionamento RTK.', 'emilid-reach-rs2-plus.webp', true, 11),
  ('javad-triumph-1', 'gnss', 'Javad', 'Triumph-1', 'Receptor GNSS geodésico para rastreio estático e apoio de campo.', 'javad-trimph-1.webp', true, 12),
  ('hi-target-v200', 'gnss', 'Hi-Target', 'V200', 'Receptor GNSS para posicionamento RTK.', null, true, 13),
  ('receptor-gnss-trimble', 'gnss', 'Receptor GNSS', 'Trimble', 'Receptor GPS.', null, true, 14),
  ('receptor-gnss-leica', 'gnss', 'Receptor GNSS', 'Leica', 'Receptor GPS de sinais de constelações com capacidade de correção.', null, true, 15),
  ('receptor-gnss-sem-marca', 'gnss', 'Receptor GNSS', 'sem marca', 'Receptor GPS para medição geodésica, com 02 receptores com 02 bolsas de temperatura.', null, true, 16),
  ('topcon-dl-502', 'nivel', 'Topcon', 'DL-502', 'Nível digital para nivelamento geométrico.', 'nivel-topcon-dl-502.webp', true, 17),
  ('nivel-zeiss', 'nivel', 'Nível', 'Zeiss', 'Nível para topografia acondicionado em caixa de madeira. cor: cinza.', null, true, 18),
  ('nivel-foif', 'nivel', 'Nível', 'Foif', 'Nível óptico.', null, true, 19),
  ('nivel-kern', 'nivel', 'Nível', 'Kern', 'Nível para topografia, acondicionado em caixa plástica. cor: marrom/verde.', null, true, 20),
  ('nivel-sem-marca', 'nivel', 'Nível', 'sem marca', 'Nível para topografia, automático, para levantamento de média precisão com acessórios, caixa em madeira e tripé tambem em madeira tipo - k002. cor: cinza.', null, true, 21),
  ('luneta-de-nivel-niveltec', 'nivel', 'Luneta de nível', 'Niveltec', 'Luneta, com tripé, altura regulável, com capa, acompanhada de uma mira em PVC de 2,5m. cor: preta.', null, true, 22),
  ('nivel-sion', 'nivel', 'Nível', 'Sion', 'Nível para topografia, com giro de 360 graus e 1 luneta, estojo de madiera portátil com chave. cor: laranja.', null, true, 23),
  ('nivel-gurley', 'nivel', 'Nível', 'Gurley', 'Nível para topografia, de luneta, em metal amarela, com tripé(para fins didáticos). cor: amarelo.', null, true, 24),
  ('nivel-mitutoyo', 'nivel', 'Nível', 'Mitutoyo', 'Nível de pedreiro metálico, precisão 0.02mm/m, em estojo de madeira envernizado. cor: cinza dimensões: 0,20x0,04x0,04 m.', null, true, 25),
  ('nivel-mom', 'nivel', 'Nível', 'MOM', 'Nível para topografia, pequeno instrumento de nivelacao automática, em estojo de couro. cor: vermelha.', null, true, 26),
  ('nivel-pzo', 'nivel', 'Nível', 'PZO', 'Nível para topografia com objetiva auxiliar acoplada na base,capa plástica, acondicionado em caixa metálica com alça e trincos, equipado com 1 mira falante extensiva em madeira envernizada 4m de altura pat.', null, true, 27),
  ('nivel-siom', 'nivel', 'Nível', 'Siom', 'Nível para topografia, escala de 0 a 350 graus, em estojo e tripé em madeira e pontas de ferro. cor: laranja.', null, true, 28),
  ('nivel-wild', 'nivel', 'Nível', 'Wild', 'Nível topográfico acondicionado em caixa de plástico.', null, true, 29),
  ('teodolito-berger', 'teodolito', 'Teodolito', 'Berger', 'Teodolito digital, com prumo óptico, leitura digital de 10 segundos, com porcentagem de rampa, com estojo para aconcionamento, proteção e transporte, com tripé de alumínio.', null, true, 30),
  ('teodolito-world', 'teodolito', 'Teodolito', 'World', 'Teodolito de leitura externa, escala de 0 a 360 graus, precisão de 1 minuto, com bússola. cor: bege.', null, true, 31),
  ('teodolito-sem-marca', 'teodolito', 'Teodolito', 'sem marca', 'Teodolito taqueômetro de alta precisão, com acessórios, tripé em madeira k-001, em caixa de madeira. cor: cinza.', null, true, 32),
  ('teodolito-vasconcelos', 'teodolito', 'Teodolito', 'Vasconcelos', 'Teodolito, com limbos externos, aproximadamente de 1 minuto no limbo horizontal e no vertical, em estojo metálico tipo campanula de cor cinza e preta com tripé em madeira, altura regulável. cor: cinza.', null, true, 33),
  ('teodolito-dfv', 'teodolito', 'Teodolito', 'DFV', 'Teodolito repetidor, ajustável, com bússola e luneta em caixa cinza e preta portátil, tripé regulável em madeira cor: cinza.', null, true, 34),
  ('teodolito-wild', 'teodolito', 'Teodolito', 'Wild', 'Teodolito, com limbos internos, aproximadamente de 1 minuto nos limbos horizontais e verticais, luneta autoredutor, em caixa metálica tipo campanula cor verde, com tripé em madeiraaltura regulável.', null, true, 35),
  ('teodolito-zeiss', 'teodolito', 'Teodolito', 'Zeiss', 'Teodolito, com limbos internos em caixa metálica tipo maleta de cor azul, com tripé de madeira, altura regulável. cor: cinza.', null, true, 36),
  ('teodolito-keuffel', 'teodolito', 'Teodolito', 'Keuffel', 'Teodolito, com limbos internos, aproximadamente de 1 minuto no limbo horizontal e no vertical, em caixa metálica tipo campanula cor verde, com tripé de madeira, altura regulável.', null, true, 37),
  ('teodolito-sunray', 'teodolito', 'Teodolito', 'Sunray', 'Teodolito, com limbo externo, aproximadamente de 20 segundos no limbo horizontal e 1 minuto no limbo vertical, acondicionado em caixa tipo maleta, bolsa a tira colo cor laranja, com tripé de madeira, altura regulável.', null, true, 38),
  ('teodolito-breithaupt', 'teodolito', 'Teodolito', 'Breithaupt', 'Teodolito metálico com bússola, base de madeira.', null, true, 39),
  ('teodolito-mon-richer', 'teodolito', 'Teodolito', 'Mon Richer', 'Teodolito, metálico (para fins didáticos). cor: bronzeado.', null, true, 40),
  ('teodolito-oms', 'teodolito', 'Teodolito', 'OMS', 'Teodolito, base de ferro (para fins didáticos). cor: cinza.', null, true, 41),
  ('teodolito-zeiss-jena', 'teodolito', 'Teodolito', 'Zeiss Jena', 'Teodolito de escala, micrométrico, 7 ajustes, procedência alemã.', null, true, 42),
  ('teodolito-zuhio', 'teodolito', 'Teodolito', 'Zuhio', 'Teodolito, em caixa de madeira, com tripé e bússola com limbos externos e sessenta segundos no limbo interno. cor: cinza.', null, true, 43),
  ('riegl-vz-400', 'laser-scanner', 'Riegl', 'VZ-400', 'Laser scanner terrestre para nuvens de pontos.', 'riegl-vz-400.webp', true, 44),
  ('batmap-ii', 'aeronave', 'Batmap', 'II', 'VANT de asa fixa para aerolevantamento.', 'batmap-ii.webp', true, 45),
  ('dji-mavic-air-2', 'aeronave', 'DJI', 'Mavic Air 2', 'Drone multirrotor para imagens aéreas.', 'drone-dji-mavic-air-2.webp', true, 46),
  ('bussola-passed', 'medicao', 'Bússola', 'Passed', 'Bússola com luneta, tipo brunton, origem japonesa, disco de 50 a 50, acondicionada com bolsa de couro marrom, com tripé em madeira envernizada e altura regulável. cor: verde e preta.', null, true, 47),
  ('trena-eletronica-leica', 'medicao', 'Trena eletrônica', 'Leica', 'Trena eletrônica.', null, true, 48),
  ('altimetro-sem-marca', 'medicao', 'Altímetro', 'sem marca', 'Altímetro, com escala de metro em metro e de 5 em 5 metros, acondicionado em bolsa de couro. cor: alumínio.', null, true, 49),
  ('altimetro-wallace', 'medicao', 'Altímetro', 'Wallace', 'Altímetro de precisão com termômetro de bulbo seco e bulbo úmido, acondicionado em caixa metálica. cor: verde.', null, true, 50),
  ('bussola-ushikata', 'medicao', 'Bússola', 'Ushikata', 'Bússola com luneta, acondicionado em estojo de couro preto, com escala de 360 graus, luneta com objetiva de 18m/m, escaladupla de 0 a 50 graus, tripé metálico regulável com capa de tecido amarelo com alça. cor: bege.', null, true, 51),
  ('pantometro-sem-marca', 'medicao', 'Pantômetro', 'sem marca', 'Pantômetro, com luneta e bússola, metálico, base de ferro, tripé de madeira. cor: cinza.', null, true, 52),
  ('podometro-teiluiz', 'medicao', 'Podômetro', 'Teiluiz', 'Podômetro 0-40km, aparelho para medir distância em junção de número de passos dados.', null, true, 53),
  ('prancheta-topografica-sem-marca', 'medicao', 'Prancheta topográfica', 'sem marca', 'Prancheta topográfica, caixa em madeira, bolsa em lona, tripé em madeira, tipo k-014. cor: cinza.', null, true, 54),
  ('binoculo-bushnell', 'medicao', 'Binóculo', 'Bushnell', 'Binóculo com diâmetro de 35mm, aumento 7x15 vezes com zoom, com tampa protetora das lentes, acompanha bolsa em courvin para acondicionamento. cor: preto.', null, true, 55),
  ('bussola-fuji', 'medicao', 'Bússola', 'Fuji', 'Bússola com tripé, 0-360 graus, com luneta. cor: cinza.', null, true, 56),
  ('bussola-osaka-tamaya', 'medicao', 'Bússola', 'Osaka-Tamaya', 'Bússola com tripé, 0-360 graus, com luneta. cor: cinza.', null, true, 57),
  ('clinometro-casella', 'medicao', 'Clinômetro', 'Casella', 'Clinômetro metálico com escala de 0 a 90 graus, acondicionado em caixa de madeira revestida em plástico.', null, true, 58),
  ('clinometro-fuji', 'medicao', 'Clinômetro', 'Fuji', 'Clinômetro de pêndulo, com escala espelhada de 0 a 50, metálico, com bússola número 25, em caixa de couro. cor: cinza.', null, true, 59),
  ('clinometro-meridian', 'medicao', 'Clinômetro', 'Meridian', 'Clinômetro (clisímetro) portátil com bolsa de couro para seu acondicionamento.', null, true, 60),
  ('medidor-topografico-genovesi', 'medicao', 'Medidor topográfico', 'Genovesi', 'Medidor topográfico, com leituras parciais em decímetros, capacidade máxima do registrador 10 km cor laranja.', null, true, 61),
  ('telemetro-wild', 'medicao', 'Telêmetro', 'Wild', 'Telêmetro com cabeçote, marca Wild, com limbos externos horizontais e verticais em estojo metálico.', null, true, 62),
  ('tripe-miratec', 'acessorio', 'Tripé', 'Miratec', 'Tripé para teodolito, com pernas extensíveis em alumínio, com placa de apoio do instrumento e parafusos de fixação.', null, true, 63),
  ('mira-foif', 'acessorio', 'Mira', 'Foif', 'Mira uso topográfico, material alumínio, tipo encaixe, comprimento 4 m, aplicação topografia e agrimensura.', null, true, 64),
  ('baliza-sem-marca', 'acessorio', 'Baliza', 'sem marca', 'Baliza topográfica, cor branca/vermelha, 3/4", metálica, com 10 hastes, cor branca/vermelha, 3/4", metálica.', null, true, 65),
  ('mira-desetec-trident', 'acessorio', 'Mira', 'Desetec/Trident', 'Mira topográfica, tipo encaixe, 3 metros de comprimento, em madeira graduada de 01 em 01 cm, base metálica.', null, true, 66),
  ('mira-sem-marca', 'acessorio', 'Mira', 'sem marca', 'Mira topográfica, metálica, de invar, inteiriça 4m. cor: laranja.', null, true, 67),
  ('tripe-cst', 'acessorio', 'Tripé', 'CST', 'Tripé cabeça hidráulica, material em duralumínio, base em meia esfera engate rápido, altura máxima 1,90 m, bolsa de transporte.', null, true, 68),
  ('tripe-desetec-trident', 'acessorio', 'Tripé', 'Desetec/Trident', 'Tripé para equipamentos topográficos, em madeira, 3 torniquetes, 3 pés metalicos, em bolsa de couro com acessorio. cor: amarela.', null, true, 69),
  ('mira-mom', 'acessorio', 'Mira', 'MOM', 'Mira para leitura graduada, dobrável envernizada. cor verde.', null, true, 70),
  ('mira-zeiss', 'acessorio', 'Mira', 'Zeiss', 'Mira topográfica falante, 175cm, precisão 1cm, equipada com 1nivel e base de pretecao, em caixa de madeira. cor: amarela.', null, true, 71),
  ('micrometro-optico-mom', 'acessorio', 'Micrômetro óptico', 'MOM', 'Micrômetro óptico, para níveis de NI-B3, 4, 5, 6 em estojo de couro. cor: cinza.', null, true, 72),
  ('mira-miratec', 'acessorio', 'Mira', 'Miratec', 'Mira falante em madeira envernizada, com 3 peças de encaixar, medindo 3 metros. cor clara dimensões: 400x8x4,7 cm.', null, true, 73),
  ('base-topografica-mom', 'acessorio', 'Base topográfica', 'MOM', 'Base para medição topográfica, sem tripé, em caixa de madeira sem alça. cor: cinza.', null, true, 74),
  ('mira-amapal', 'acessorio', 'Mira', 'Amapal', 'Mira topográfica, dobrável, em alumínio, graduada, portátil. cor: cinza.', null, true, 75),
  ('oculares-mom', 'acessorio', 'Oculares', 'MOM', 'Conjunto de oculares de ângulos, em caixa de madeira. cor: cinza.', null, true, 76),
  ('oculares-sem-marca', 'acessorio', 'Oculares', 'sem marca', 'Estojo de oculares de cotovelo, composto de duas peças, referências: 704127 e 704211, em estojo de madeira aglomerada. cor: cinza e preta dimensões do estojo: 0,15x0,08x0,04 m.', null, true, 77),
  ('prisma-pentax', 'acessorio', 'Prisma', 'Pentax', 'Equipamento diversos para serviços profissionais, prisma para estação total.', null, true, 78),
  ('prumo-zenital-sem-marca', 'acessorio', 'Prumo zenital', 'sem marca', 'Prumo zenital óptico de precisão.', null, true, 79),
  ('tripe-sem-marca', 'acessorio', 'Tripé', 'sem marca', 'Tripé para equipamentos topográficos, em madeira envernizada, ref 20, estrutura metálica, 3 torniquetes. cor: verde.', null, true, 80),
  ('tripe-techgeo', 'acessorio', 'Tripé', 'Techgeo', 'Tripé para GPS, componente para o sistema RTK GTR-G2.', null, true, 81),
  ('tripe-trident', 'acessorio', 'Tripé', 'Trident', 'Tripé para equipamentos topográficos, em madeira acompanhado de 1 chave halem e 1 fio de plumo. cor: amarela.', null, true, 82),
  ('tripe-world', 'acessorio', 'Tripé', 'World', 'Tripé topográfico, em madeira pintada, regulável, pés com ponteira metálica. cor: laranja.', null, true, 83),
  ('planimetro-k-pluse', 'desenho', 'Planímetro', 'K+E', 'Planímetro compensado, acondicionado em estojo de madeira revestido em plástico, serial 51361. cor: verde.', null, true, 84),
  ('planimetro-mom', 'desenho', 'Planímetro', 'MOM', 'Planímetro, acondicionado em caixa de madeira revestida em plástico. cor: preta.', null, true, 85),
  ('planimetro-sem-marca', 'desenho', 'Planímetro', 'sem marca', 'Planímetro g. coradi ag zurich. acondicionado em estojo em madeira, com revestimento em plástico. cor: cinza.', null, true, 86),
  ('planimetro-tama-sokki', 'desenho', 'Planímetro', 'Tama Sokki', 'Planímetro, acondicionado em caixa de madeira revestida em plástico. cor: cinza.', null, true, 87),
  ('estereoscopio-zeiss', 'desenho', 'Estereoscópio', 'Zeiss', 'Estereoscópio de restituição, para fotografias até 30 x 30cm,composto de 1 estereoscópio de espelho com 2 oculares de 3.5 x 15 e 4 hastess para sustencao, 1 estereopantometro de desenho com guia paralela e 4 rodizios.', null, true, 88),
  ('normografo-leroy-keuffel-esser', 'desenho', 'Normógrafo', 'Leroy/Keuffel & Esser', 'Normógrafo, acondicionado em estojo de madeira envernizada, com 11 réguas, 11 penas, 1 aranha, 1 portatinta e 1 ponteirade grafite.', null, true, 89),
  ('normografo-trident', 'desenho', 'Normógrafo', 'Trident', 'Normógrafo completo em estojo de madeira envernizada, com 11 réguas, 10 penas com os seguintes números: 0.3 a 0.8; 1.0; 1.2; 1.5 e 1.8. dimensões do estojo: 0,44x0,17x0,06m.', null, true, 90),
  ('planimetro-ansler', 'desenho', 'Planímetro', 'Ansler', 'Planímetro, acondicionado em estojo de madeira revestido em plástico. cor: preta.', null, true, 91),
  ('regua-de-escala-kern', 'desenho', 'Régua de escala', 'Kern', 'Régua de escala topográfica, metálica, um transferidor metálico de 180 graus, um compasso bomba, 1 estojo para ponta seca,1 cintel, 1 alfinete para copia, 2 compassos para lapis, 1 compasso de linha pararelas.', null, true, 92),
  ('bosch-martelete', 'apoio', 'Bosch', 'Martelete', 'Martelete perfurador e rompedor para implantação de marcos e pinos.', 'martelete-bosch.webp', true, 93),
  ('buffalo-bfg-2500', 'apoio', 'Buffalo', 'BFG 2500', 'Gerador a gasolina para energia em campo.', 'gerador-buffalo-bfg-2500.webp', true, 94),
  ('camera-digital-nikon', 'apoio', 'Câmera digital', 'Nikon', 'Câmera digital.', null, true, 95)
on conflict (id) do update set categoria_id = excluded.categoria_id, marca = excluded.marca, nome = excluded.nome,
  descricao = excluded.descricao, foto = excluded.foto, emprestavel = excluded.emprestavel, ordem = excluded.ordem;

delete from unidades;
delete from modelos where id not in ('geodetic-gd2i', 'geodetic-gt2-plus', 'geodetic-gd8i', 'topcon-es-65', 'topcon-gts-102n', 'topcon-gts-212', 'estacao-total-pentax', 'chc-i50', 'topomap-t10', 'emlid-reach-rs2', 'emlid-reach-rs2-plus', 'javad-triumph-1', 'hi-target-v200', 'receptor-gnss-trimble', 'receptor-gnss-leica', 'receptor-gnss-sem-marca', 'topcon-dl-502', 'nivel-zeiss', 'nivel-foif', 'nivel-kern', 'nivel-sem-marca', 'luneta-de-nivel-niveltec', 'nivel-sion', 'nivel-gurley', 'nivel-mitutoyo', 'nivel-mom', 'nivel-pzo', 'nivel-siom', 'nivel-wild', 'teodolito-berger', 'teodolito-world', 'teodolito-sem-marca', 'teodolito-vasconcelos', 'teodolito-dfv', 'teodolito-wild', 'teodolito-zeiss', 'teodolito-keuffel', 'teodolito-sunray', 'teodolito-breithaupt', 'teodolito-mon-richer', 'teodolito-oms', 'teodolito-zeiss-jena', 'teodolito-zuhio', 'riegl-vz-400', 'batmap-ii', 'dji-mavic-air-2', 'bussola-passed', 'trena-eletronica-leica', 'altimetro-sem-marca', 'altimetro-wallace', 'bussola-ushikata', 'pantometro-sem-marca', 'podometro-teiluiz', 'prancheta-topografica-sem-marca', 'binoculo-bushnell', 'bussola-fuji', 'bussola-osaka-tamaya', 'clinometro-casella', 'clinometro-fuji', 'clinometro-meridian', 'medidor-topografico-genovesi', 'telemetro-wild', 'tripe-miratec', 'mira-foif', 'baliza-sem-marca', 'mira-desetec-trident', 'mira-sem-marca', 'tripe-cst', 'tripe-desetec-trident', 'mira-mom', 'mira-zeiss', 'micrometro-optico-mom', 'mira-miratec', 'base-topografica-mom', 'mira-amapal', 'oculares-mom', 'oculares-sem-marca', 'prisma-pentax', 'prumo-zenital-sem-marca', 'tripe-sem-marca', 'tripe-techgeo', 'tripe-trident', 'tripe-world', 'planimetro-k-pluse', 'planimetro-mom', 'planimetro-sem-marca', 'planimetro-tama-sokki', 'estereoscopio-zeiss', 'normografo-leroy-keuffel-esser', 'normografo-trident', 'planimetro-ansler', 'regua-de-escala-kern', 'bosch-martelete', 'buffalo-bfg-2500', 'camera-digital-nikon')
  and id not in (select modelo_id from disciplina_equipamentos);
delete from categorias where id not in ('estacao-total', 'gnss', 'nivel', 'teodolito', 'laser-scanner', 'aeronave', 'medicao', 'acessorio', 'desenho', 'apoio')
  and id not in (select categoria_id from modelos);

insert into unidades (modelo_id, patrimonio, numero_serie, situacao, observacao) values
  ('geodetic-gd2i', null, 'EX-001', 'disponivel', null),
  ('geodetic-gd2i', null, 'EX-002', 'disponivel', null),
  ('geodetic-gd2i', null, 'EX-003', 'disponivel', null),
  ('geodetic-gd2i', null, 'EX-004', 'disponivel', null),
  ('geodetic-gd2i', null, 'EX-005', 'disponivel', null),
  ('geodetic-gd2i', null, 'EX-006', 'disponivel', null),
  ('geodetic-gt2-plus', null, 'EX-007', 'disponivel', null),
  ('geodetic-gt2-plus', null, 'EX-008', 'disponivel', null),
  ('geodetic-gt2-plus', null, 'EX-009', 'disponivel', null),
  ('geodetic-gt2-plus', null, 'EX-010', 'disponivel', null),
  ('geodetic-gt2-plus', null, 'EX-011', 'disponivel', null),
  ('geodetic-gd8i', null, 'EX-012', 'disponivel', null),
  ('geodetic-gd8i', null, 'EX-013', 'disponivel', null),
  ('estacao-total-pentax', null, 'EX-014', 'disponivel', null),
  ('topcon-es-65', null, 'EX-015', 'disponivel', null),
  ('topcon-gts-102n', null, 'EX-016', 'disponivel', null),
  ('topcon-gts-212', null, 'EX-017', 'disponivel', null),
  ('chc-i50', null, 'EX-018', 'disponivel', null),
  ('chc-i50', null, 'EX-019', 'disponivel', 'Sem número de patrimônio na planilha.'),
  ('topomap-t10', null, 'EX-020', 'disponivel', null),
  ('topomap-t10', null, 'EX-021', 'disponivel', null),
  ('emlid-reach-rs2', null, 'EX-022', 'disponivel', null),
  ('emlid-reach-rs2-plus', null, 'EX-023', 'disponivel', null),
  ('javad-triumph-1', null, 'EX-024', 'disponivel', null),
  ('hi-target-v200', null, 'EX-025', 'disponivel', null),
  ('hi-target-v200', null, 'EX-026', 'disponivel', null),
  ('receptor-gnss-trimble', null, 'EX-027', 'disponivel', null),
  ('receptor-gnss-trimble', null, 'EX-028', 'disponivel', null),
  ('receptor-gnss-leica', null, 'EX-029', 'disponivel', null),
  ('receptor-gnss-sem-marca', null, 'EX-030', 'disponivel', null),
  ('nivel-zeiss', null, 'EX-031', 'disponivel', null),
  ('nivel-zeiss', null, 'EX-032', 'disponivel', null),
  ('nivel-zeiss', null, 'EX-033', 'disponivel', null),
  ('nivel-zeiss', null, 'EX-034', 'disponivel', null),
  ('nivel-zeiss', null, 'EX-035', 'disponivel', null),
  ('nivel-zeiss', null, 'EX-036', 'disponivel', null),
  ('nivel-zeiss', null, 'EX-037', 'disponivel', null),
  ('nivel-zeiss', null, 'EX-038', 'disponivel', null),
  ('nivel-foif', null, 'EX-039', 'disponivel', null),
  ('nivel-foif', null, 'EX-040', 'disponivel', null),
  ('nivel-foif', null, 'EX-041', 'disponivel', null),
  ('nivel-foif', null, 'EX-042', 'disponivel', null),
  ('nivel-mom', null, 'EX-043', 'disponivel', null),
  ('nivel-siom', null, 'EX-044', 'disponivel', null),
  ('nivel-wild', null, 'EX-045', 'disponivel', null),
  ('topcon-dl-502', null, 'EX-046', 'disponivel', 'Sem número de patrimônio na planilha.'),
  ('nivel-kern', null, 'EX-047', 'disponivel', null),
  ('nivel-kern', null, 'EX-048', 'disponivel', null),
  ('nivel-kern', null, 'EX-049', 'disponivel', null),
  ('nivel-sem-marca', null, 'EX-050', 'disponivel', null),
  ('nivel-sem-marca', null, 'EX-051', 'disponivel', null),
  ('nivel-sem-marca', null, 'EX-052', 'disponivel', null),
  ('luneta-de-nivel-niveltec', null, 'EX-053', 'disponivel', null),
  ('luneta-de-nivel-niveltec', null, 'EX-054', 'disponivel', null),
  ('nivel-sion', null, 'EX-055', 'disponivel', null),
  ('nivel-sion', null, 'EX-056', 'disponivel', null),
  ('nivel-gurley', null, 'EX-057', 'disponivel', null),
  ('nivel-mitutoyo', null, 'EX-058', 'disponivel', null),
  ('nivel-pzo', null, 'EX-059', 'disponivel', null),
  ('teodolito-berger', null, 'EX-060', 'disponivel', null),
  ('teodolito-berger', null, 'EX-061', 'disponivel', null),
  ('teodolito-berger', null, 'EX-062', 'disponivel', null),
  ('teodolito-berger', null, 'EX-063', 'disponivel', null),
  ('teodolito-berger', null, 'EX-064', 'disponivel', null),
  ('teodolito-berger', null, 'EX-065', 'disponivel', null),
  ('teodolito-berger', null, 'EX-066', 'disponivel', null),
  ('teodolito-berger', null, 'EX-067', 'disponivel', null),
  ('teodolito-berger', null, 'EX-068', 'disponivel', null),
  ('teodolito-berger', null, 'EX-069', 'disponivel', null),
  ('teodolito-berger', null, 'EX-070', 'disponivel', null),
  ('teodolito-berger', null, 'EX-071', 'disponivel', null),
  ('teodolito-berger', null, 'EX-072', 'disponivel', null),
  ('teodolito-berger', null, 'EX-073', 'disponivel', null),
  ('teodolito-berger', null, 'EX-074', 'disponivel', null),
  ('teodolito-berger', null, 'EX-075', 'disponivel', null),
  ('teodolito-berger', null, 'EX-076', 'disponivel', null),
  ('teodolito-berger', null, 'EX-077', 'disponivel', null),
  ('teodolito-berger', null, 'EX-078', 'disponivel', null),
  ('teodolito-berger', null, 'EX-079', 'disponivel', null),
  ('teodolito-world', null, 'EX-080', 'disponivel', null),
  ('teodolito-world', null, 'EX-081', 'disponivel', null),
  ('teodolito-world', null, 'EX-082', 'disponivel', null),
  ('teodolito-world', null, 'EX-083', 'manutencao', 'Consta como "Com defeito" no patrimônio.'),
  ('teodolito-world', null, 'EX-084', 'disponivel', null),
  ('teodolito-world', null, 'EX-085', 'disponivel', null),
  ('teodolito-world', null, 'EX-086', 'manutencao', 'Consta como "Com defeito" no patrimônio.'),
  ('teodolito-world', null, 'EX-087', 'disponivel', null),
  ('teodolito-vasconcelos', null, 'EX-088', 'disponivel', null),
  ('teodolito-vasconcelos', null, 'EX-089', 'disponivel', null),
  ('teodolito-vasconcelos', null, 'EX-090', 'disponivel', null),
  ('teodolito-vasconcelos', null, 'EX-091', 'disponivel', null),
  ('teodolito-vasconcelos', null, 'EX-092', 'disponivel', null),
  ('teodolito-vasconcelos', null, 'EX-093', 'disponivel', null),
  ('teodolito-wild', null, 'EX-094', 'disponivel', null),
  ('teodolito-wild', null, 'EX-095', 'disponivel', null),
  ('teodolito-wild', null, 'EX-096', 'disponivel', null),
  ('teodolito-wild', null, 'EX-097', 'disponivel', null),
  ('teodolito-zeiss', null, 'EX-098', 'disponivel', null),
  ('teodolito-zeiss', null, 'EX-099', 'disponivel', null),
  ('teodolito-zeiss', null, 'EX-100', 'disponivel', null),
  ('teodolito-zeiss', null, 'EX-101', 'disponivel', null),
  ('teodolito-zeiss-jena', null, 'EX-102', 'disponivel', null),
  ('teodolito-sem-marca', null, 'EX-103', 'disponivel', null),
  ('teodolito-sem-marca', null, 'EX-104', 'disponivel', null),
  ('teodolito-sem-marca', null, 'EX-105', 'disponivel', null),
  ('teodolito-sem-marca', null, 'EX-106', 'disponivel', null),
  ('teodolito-sem-marca', null, 'EX-107', 'disponivel', null),
  ('teodolito-sem-marca', null, 'EX-108', 'disponivel', null),
  ('teodolito-dfv', null, 'EX-109', 'disponivel', null),
  ('teodolito-dfv', null, 'EX-110', 'disponivel', null),
  ('teodolito-dfv', null, 'EX-111', 'disponivel', null),
  ('teodolito-dfv', null, 'EX-112', 'disponivel', null),
  ('teodolito-keuffel', null, 'EX-113', 'disponivel', null),
  ('teodolito-keuffel', null, 'EX-114', 'disponivel', null),
  ('teodolito-keuffel', null, 'EX-115', 'disponivel', null),
  ('teodolito-sunray', null, 'EX-116', 'disponivel', null),
  ('teodolito-sunray', null, 'EX-117', 'disponivel', null),
  ('teodolito-sunray', null, 'EX-118', 'disponivel', null),
  ('teodolito-breithaupt', null, 'EX-119', 'disponivel', null),
  ('teodolito-mon-richer', null, 'EX-120', 'disponivel', null),
  ('teodolito-oms', null, 'EX-121', 'disponivel', null),
  ('teodolito-zuhio', null, 'EX-122', 'disponivel', null),
  ('riegl-vz-400', null, 'EX-123', 'disponivel', null),
  ('batmap-ii', null, 'EX-124', 'manutencao', 'Consta como "Com defeito" no patrimônio.'),
  ('dji-mavic-air-2', null, 'EX-125', 'disponivel', null),
  ('binoculo-bushnell', null, 'EX-126', 'disponivel', null),
  ('telemetro-wild', null, 'EX-127', 'disponivel', null),
  ('bussola-passed', null, 'EX-128', 'disponivel', null),
  ('bussola-passed', null, 'EX-129', 'disponivel', null),
  ('bussola-passed', null, 'EX-130', 'disponivel', null),
  ('bussola-passed', null, 'EX-131', 'disponivel', null),
  ('bussola-passed', null, 'EX-132', 'disponivel', null),
  ('trena-eletronica-leica', null, 'EX-133', 'disponivel', null),
  ('trena-eletronica-leica', null, 'EX-134', 'disponivel', null),
  ('trena-eletronica-leica', null, 'EX-135', 'disponivel', null),
  ('trena-eletronica-leica', null, 'EX-136', 'disponivel', null),
  ('altimetro-sem-marca', null, 'EX-137', 'disponivel', null),
  ('altimetro-sem-marca', null, 'EX-138', 'disponivel', null),
  ('altimetro-wallace', null, 'EX-139', 'disponivel', null),
  ('altimetro-wallace', null, 'EX-140', 'disponivel', null),
  ('bussola-ushikata', null, 'EX-141', 'disponivel', null),
  ('bussola-ushikata', null, 'EX-142', 'disponivel', null),
  ('pantometro-sem-marca', null, 'EX-143', 'disponivel', null),
  ('pantometro-sem-marca', null, 'EX-144', 'disponivel', null),
  ('podometro-teiluiz', null, 'EX-145', 'disponivel', null),
  ('podometro-teiluiz', null, 'EX-146', 'disponivel', null),
  ('prancheta-topografica-sem-marca', null, 'EX-147', 'disponivel', null),
  ('prancheta-topografica-sem-marca', null, 'EX-148', 'disponivel', null),
  ('bussola-fuji', null, 'EX-149', 'disponivel', null),
  ('bussola-osaka-tamaya', null, 'EX-150', 'disponivel', null),
  ('clinometro-casella', null, 'EX-151', 'disponivel', null),
  ('clinometro-fuji', null, 'EX-152', 'disponivel', null),
  ('clinometro-meridian', null, 'EX-153', 'disponivel', null),
  ('medidor-topografico-genovesi', null, 'EX-154', 'disponivel', null),
  ('tripe-miratec', null, 'EX-155', 'disponivel', null),
  ('tripe-miratec', null, 'EX-156', 'disponivel', null),
  ('tripe-miratec', null, 'EX-157', 'disponivel', null),
  ('tripe-miratec', null, 'EX-158', 'disponivel', null),
  ('tripe-miratec', null, 'EX-159', 'disponivel', null),
  ('tripe-miratec', null, 'EX-160', 'disponivel', null),
  ('tripe-miratec', null, 'EX-161', 'disponivel', null),
  ('tripe-miratec', null, 'EX-162', 'disponivel', null),
  ('mira-foif', null, 'EX-163', 'disponivel', null),
  ('mira-foif', null, 'EX-164', 'disponivel', null),
  ('mira-foif', null, 'EX-165', 'disponivel', null),
  ('mira-foif', null, 'EX-166', 'disponivel', null),
  ('mira-foif', null, 'EX-167', 'disponivel', null),
  ('baliza-sem-marca', null, 'EX-168', 'disponivel', null),
  ('baliza-sem-marca', null, 'EX-169', 'disponivel', null),
  ('baliza-sem-marca', null, 'EX-170', 'disponivel', null),
  ('baliza-sem-marca', null, 'EX-171', 'disponivel', null),
  ('mira-desetec-trident', null, 'EX-172', 'disponivel', null),
  ('mira-desetec-trident', null, 'EX-173', 'disponivel', null),
  ('mira-desetec-trident', null, 'EX-174', 'disponivel', null),
  ('mira-desetec-trident', null, 'EX-175', 'disponivel', null),
  ('mira-sem-marca', null, 'EX-176', 'disponivel', null),
  ('mira-sem-marca', null, 'EX-177', 'disponivel', null),
  ('mira-sem-marca', null, 'EX-178', 'disponivel', null),
  ('mira-sem-marca', null, 'EX-179', 'disponivel', null),
  ('tripe-cst', null, 'EX-180', 'disponivel', null),
  ('tripe-cst', null, 'EX-181', 'disponivel', null),
  ('tripe-cst', null, 'EX-182', 'disponivel', null),
  ('tripe-cst', null, 'EX-183', 'disponivel', null),
  ('tripe-desetec-trident', null, 'EX-184', 'disponivel', null),
  ('tripe-desetec-trident', null, 'EX-185', 'disponivel', null),
  ('tripe-desetec-trident', null, 'EX-186', 'disponivel', null),
  ('tripe-desetec-trident', null, 'EX-187', 'disponivel', null),
  ('mira-mom', null, 'EX-188', 'disponivel', null),
  ('mira-mom', null, 'EX-189', 'disponivel', null),
  ('mira-mom', null, 'EX-190', 'disponivel', null),
  ('mira-zeiss', null, 'EX-191', 'disponivel', null),
  ('mira-zeiss', null, 'EX-192', 'disponivel', null),
  ('mira-zeiss', null, 'EX-193', 'disponivel', null),
  ('micrometro-optico-mom', null, 'EX-194', 'disponivel', null),
  ('micrometro-optico-mom', null, 'EX-195', 'disponivel', null),
  ('mira-miratec', null, 'EX-196', 'disponivel', null),
  ('mira-miratec', null, 'EX-197', 'disponivel', null),
  ('base-topografica-mom', null, 'EX-198', 'disponivel', null),
  ('mira-amapal', null, 'EX-199', 'disponivel', null),
  ('oculares-mom', null, 'EX-200', 'disponivel', null),
  ('oculares-sem-marca', null, 'EX-201', 'disponivel', null),
  ('prisma-pentax', null, 'EX-202', 'disponivel', null),
  ('prumo-zenital-sem-marca', null, 'EX-203', 'disponivel', null),
  ('tripe-sem-marca', null, 'EX-204', 'disponivel', null),
  ('tripe-techgeo', null, 'EX-205', 'disponivel', null),
  ('tripe-trident', null, 'EX-206', 'disponivel', null),
  ('tripe-world', null, 'EX-207', 'disponivel', null),
  ('planimetro-k-pluse', null, 'EX-208', 'disponivel', null),
  ('planimetro-k-pluse', null, 'EX-209', 'disponivel', null),
  ('planimetro-k-pluse', null, 'EX-210', 'disponivel', null),
  ('planimetro-k-pluse', null, 'EX-211', 'disponivel', null),
  ('planimetro-k-pluse', null, 'EX-212', 'disponivel', null),
  ('planimetro-mom', null, 'EX-213', 'disponivel', null),
  ('planimetro-mom', null, 'EX-214', 'disponivel', null),
  ('planimetro-sem-marca', null, 'EX-215', 'disponivel', null),
  ('planimetro-sem-marca', null, 'EX-216', 'disponivel', null),
  ('planimetro-tama-sokki', null, 'EX-217', 'disponivel', null),
  ('planimetro-tama-sokki', null, 'EX-218', 'disponivel', null),
  ('estereoscopio-zeiss', null, 'EX-219', 'disponivel', null),
  ('normografo-leroy-keuffel-esser', null, 'EX-220', 'disponivel', null),
  ('normografo-trident', null, 'EX-221', 'disponivel', null),
  ('planimetro-ansler', null, 'EX-222', 'disponivel', null),
  ('regua-de-escala-kern', null, 'EX-223', 'disponivel', null),
  ('bosch-martelete', null, 'EX-224', 'disponivel', null),
  ('buffalo-bfg-2500', null, 'EX-225', 'disponivel', null),
  ('camera-digital-nikon', null, 'EX-226', 'disponivel', null);

create or replace function salvar_perfil(p_nome text, p_matricula text, p_telefone text, p_vinculo text)
returns pessoas language plpgsql security definer set search_path = public as $$
declare
  v pessoas;
  v_email text := lower(auth.jwt() ->> 'email');
begin
  if auth.uid() is null then raise exception 'Entre para continuar'; end if;
  if v_email is null or not (v_email like '%@ufv.br' or v_email like '%.ufv.br') then
    raise exception 'Use a sua conta institucional da UFV (@ufv.br)';
  end if;
  insert into pessoas (id, nome, email, matricula, telefone, vinculo)
  values (auth.uid(), trim(p_nome), v_email, nullif(trim(p_matricula), ''),
          nullif(trim(p_telefone), ''), nullif(trim(p_vinculo), ''))
  on conflict (id) do update
     set nome = excluded.nome, matricula = excluded.matricula,
         telefone = excluded.telefone, vinculo = excluded.vinculo
  returning * into v;
  return v;
end $$;

create or replace function criar_emprestimo(
  p_finalidade text, p_projeto text, p_local text,
  p_retirada date, p_devolucao date,
  p_participantes text[], p_observacao text,
  p_itens jsonb            -- [{"unidade_id": "...", "observacao": "..."}]
) returns uuid language plpgsql security definer set search_path = public as $$
declare
  v_eu pessoas;
  v_id uuid;
  v_item jsonb;
  v_unidade unidades;
  v_modelo text;
  v_total int;
  v_ocupadas int;
begin
  select * into v_eu from pessoas where id = auth.uid();
  if v_eu.id is null then raise exception 'Complete seu cadastro antes de pedir'; end if;
  if v_eu.matricula is null or v_eu.telefone is null then
    raise exception 'Informe matrícula e telefone no seu cadastro';
  end if;
  if p_retirada < current_date then raise exception 'A retirada não pode ser no passado'; end if;
  if p_devolucao < p_retirada then raise exception 'A devolução vem depois da retirada'; end if;
  if jsonb_array_length(coalesce(p_itens, '[]')) = 0 then
    raise exception 'Escolha ao menos um equipamento';
  end if;

  insert into emprestimos (codigo, solicitante_id, resp_nome, resp_matricula, resp_telefone,
                           resp_email, finalidade, projeto, local_uso, retirada_prevista,
                           devolucao_prevista, participantes, observacao)
  values ('LEA-' || to_char(current_date, 'YYYY') || '-' || lpad(nextval('emprestimo_seq')::text, 4, '0'),
          v_eu.id, v_eu.nome, v_eu.matricula, v_eu.telefone, v_eu.email,
          trim(p_finalidade), trim(p_projeto), trim(p_local), p_retirada, p_devolucao,
          coalesce(p_participantes, '{}'), nullif(trim(p_observacao), ''))
  returning id into v_id;

  for v_item in select * from jsonb_array_elements(p_itens) loop
    -- trava a unidade para dois pedidos simultâneos não levarem o mesmo aparelho
    select * into v_unidade from unidades
     where id = (v_item ->> 'unidade_id')::uuid for update;
    if v_unidade.id is null then raise exception 'Equipamento não encontrado'; end if;
    if not (select emprestavel from modelos where id = v_unidade.modelo_id) then
      raise exception 'Este equipamento não está disponível para empréstimo';
    end if;
    if v_unidade.situacao <> 'disponivel' then
      raise exception 'Unidade % fora de circulação', coalesce(v_unidade.patrimonio, v_unidade.numero_serie);
    end if;
    if exists (select 1 from ocupacao o
                where o.unidade_id = v_unidade.id
                  and o.de <= p_devolucao and o.ate >= p_retirada) then
      raise exception 'Unidade % já está comprometida nesse período',
        coalesce(v_unidade.patrimonio, v_unidade.numero_serie);
    end if;
    insert into emprestimo_itens (emprestimo_id, unidade_id, observacao)
    values (v_id, v_unidade.id, nullif(trim(v_item ->> 'observacao'), ''));
  end loop;

  -- as aulas práticas do semestre têm prioridade sobre o empréstimo
  for v_modelo in select distinct u.modelo_id from emprestimo_itens i
                    join unidades u on u.id = i.unidade_id where i.emprestimo_id = v_id loop
    select count(*) into v_total from unidades where modelo_id = v_modelo and situacao = 'disponivel';
    select count(distinct o.unidade_id) into v_ocupadas
      from ocupacao o join unidades u on u.id = o.unidade_id
     where u.modelo_id = v_modelo and o.de <= p_devolucao and o.ate >= p_retirada;
    if v_ocupadas + reserva_aulas(v_modelo, p_retirada, p_devolucao) > v_total then
      raise exception 'Não há unidades livres de % nesse período: parte delas está reservada para aulas práticas',
        (select marca || ' ' || nome from modelos where id = v_modelo);
    end if;
  end loop;

  insert into emprestimo_eventos (emprestimo_id, tipo, autor_id, autor_nome, autor_papel, observacao)
  values (v_id, 'pedido_assinado', v_eu.id, v_eu.nome, 'solicitante', nullif(trim(p_observacao), ''));

  return v_id;
end $$;
