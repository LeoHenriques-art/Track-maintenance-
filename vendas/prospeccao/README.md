# Prospeção Facitrack

Pasta de trabalho da prospeção. A rotina semanal acrescenta empresas a `leads.csv`
e escreve um relatório por semana (`AAAA-MM-DD.md`) com as mensagens prontas a enviar.

## Estados (coluna `estado` de leads.csv)

- `novo`: encontrado pela rotina, mensagem ainda não enviada.
- `enviado`: mensagem enviada por ti (atualiza `data_estado`).
- `respondeu`: houve resposta.
- `reuniao`: demonstração marcada.
- `piloto`: em piloto.
- `cliente`: pagou.
- `descartado`: não interessa (escreve o motivo em `notas`).

Para mudar o estado: edita o ficheiro no GitHub, ou diz numa conversa com o Claude
"enviei para X, Y e Z".

## Setores-alvo

Supermercados e retalho, farmácias, telecomunicações, hotéis e turismo, logística
e transportes, escolas e universidades privadas, clínicas e hospitais privados.

## Excluídos (conflito de interesses)

- Bancos, seguradoras e outras instituições financeiras.
- Fornecedores de serviços de facilities com quem o fundador lida no trabalho
  (limpeza, fumigação, manutenção, jardinagem e afins), e as suas empresas-mãe.
