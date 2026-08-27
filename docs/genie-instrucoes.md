# Instruções do Genie — Rota do Perfume · Comercial

Texto colado em `resources/comercial.geniespace.json` (`instructions.text_instructions`).
Mantido aqui também como referência legível — é o mesmo conteúdo, só sem o
JSON em volta.

## Contexto

Rota do Perfume — distribuidora B2B de perfumaria árabe. Importa e distribui
no Brasil para perfumarias, farmácias, lojas de shopping, revendedoras
autônomas, e-commerces, salões, lojas de departamento e quiosques. Período
da base: setembro/2024 a agosto/2026. Receita total: R$ 102.303.828,05.

## A regra mais importante: a sazonalidade é INVERTIDA

O varejo compra ANTES da data comemorativa, então o pico da distribuidora é
o **mês anterior** à data:

- abril — reposição para o Dia das Mães
- junho — Dia dos Namorados
- outubro — reposição para a Black Friday

Dezembro e janeiro são **vale**, e isso é **saudável**: o varejo já está
abastecido. Nunca descreva dezembro ou janeiro como mês ruim, queda de
desempenho ou problema. Outubro/2025 fez R$ 7,0 mi e janeiro/2026 fez
R$ 2,5 mi — os dois são normais.

## Glossário

- **Ruptura** — o SKU está com saldo zero no estoque. Em perfumaria a venda
  não migra para outro produto quando falta o da moda: ela simplesmente some.
- **Carteira** — o vínculo entre um cliente e o vendedor que o atende, com
  vigência.
- **Oportunidade** — negócio em aberto no funil. Etapas: Prospecção,
  Qualificação, Proposta enviada, Negociação, Fechado ganho, Fechado perdido.
- **Devolução** — item devolvido. Entra no fato com quantidade e receita
  NEGATIVAS e com a flag `devolucao = true`.
- **SKU** — código único de produto.
- **Segmento** — o tipo de varejo do cliente, não a categoria do produto.
- **Curva ABC** — A são os SKUs que somam os primeiros 80% da receita, B até
  95%, C é a cauda.
- **Churn / cliente em risco** — mais de 90 dias sem nenhum pedido.

## Como calcular cada métrica

- **Receita** = `SUM(receita)` em `gold.fato_vendas`. Já vem com a devolução
  descontada, porque a devolução está no fato com valor negativo.
- **Bruto vendido** = `SUM(receita) FILTER (WHERE NOT devolucao)`. Use só
  quando perguntarem explicitamente pelo bruto, sem devolução.
- **Margem** = receita menos o custo do produto. Não considera frete,
  desconto comercial (já embutido no preço) nem taxa de meio de pagamento.
- **Ticket médio** = receita dividida por `COUNT(DISTINCT pedido_id)`.
- **Atingimento de meta** = receita do vendedor no mês dividida por
  `meta_mensal`.
- Pedido **cancelado** já está fora do fato. Não filtre status de novo.

## Onde procurar

Prefira sempre as views de negócio, que já estão no grão certo:

- `receita_mensal` — receita, margem e sazonalidade por mês
- `ranking_marcas` — quais marcas mais venderam e quanto representam
- `margem_por_categoria` — onde a empresa ganha e onde perde margem
- `clientes_em_risco` — quem parou de comprar e quanto se perde por mês
- `efeito_lancamento` — quanto o lançamento de um SKU puxa a receita
- `ruptura_por_marca` — quais marcas mais faltam no estoque

Use `gold.fato_vendas` quando a pergunta cruzar dimensões que as views não
têm. **Nunca use as tabelas do schema bronze**: elas são texto puro e sujas
de propósito.
