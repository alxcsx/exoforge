# Exoforge Pitch Deck — Manual Operacional Agent-First (`docs/pitch/AGENTS.md`)

Este documento descreve a arquitetura, as regras editoriais, o padrão visual/tipográfico e o pipeline automatizado do pitch executivo do **Exoforge** em português (`pt-BR`). O pitch segue o modelo **agent-first**: agentes editam diretamente código e dados versionados no repositório e compilam os entregáveis finais para humanos (`.html`, `.pptx`, `.pdf` via LibreOffice e `.mp4`).

---

## 1. Filosofia Agent-First, Orquestração e Delegação

- **Código é a fonte única da verdade**: nenhuma apresentação é mantida manualmente em editores externos desconectados (Miro, Canva, Figma, PowerPoint). Toda edição narrativa, visual ou de dados acontece no repositório e é recompilada de forma determinística.
- **Planejamento no modelo mais capacitado (`pro` / modelo de planejamento) e implementação sempre delegada a agentes menores (`flash` / `flash_lite`)**:
  - Todo o **planejamento, estratégia narrativa, arquitetura visual e decisões de design** devem ser elaborados por um **modelo mais capacitado** (`pro` ou o modelo principal de planejamento).
  - Toda a **implementação** (edição de código em `pitch-storyboard.mjs` / `pitch-pptx.mjs`, ajustes de HTML em `index.html`, atualização de documentação, execução de builds e auditorias/verificações) deve ser **sempre delegada pelo orquestrador para subagentes em modelos menores (`flash` ou `flash_lite`)** com escopo claro e paralelo sempre que possível.
- **Diretriz de Orquestração com Modelos Menores (`flash` / `flash_lite`)**:
  - Para garantir velocidade, paralelismo e uso sustentável de cota, o agente coordenador deve **sempre orquestrar e delegar subtarefas bem definidas para subagentes em modelos menores (`flash` ou `flash_lite`)** ao manter documentação, HTML, scripts e auditorias do pitch.
  - **Subtarefas prioritárias para delegação a subagentes menores:**
    1. *Auditoria de links e integridade*: checagem de URLs ativas, verificação de redirects/404 e extração de metadados de fontes.
    2. *Validação estrutural e XML*: descompactar `.pptx` e validar schemas com `xmllint --noout`.
    3. *Inspeção de fontes no PDF*: checar tabelas de fontes embutidas (`pdffonts` ou `/BaseFont`) garantindo ausência de fallbacks serifados.
    4. *Sincronização de copy entre artefatos*: validar paridade textual entre `index.html`, `pitch-storyboard.mjs` e `EVIDENCIAS_E_METODOLOGIA.md`.
    5. *Relatórios de conformidade visual*: inspecionar posicionamento de elementos e ausência de sobreposições em páginas específicas do PDF.
  - O modelo principal (`pro` / coordenador) foca na estratégia de produto, refinamento de narrativa de palco (YC / Shark Tank), síntese executiva e decisões arquiteturais de alto impacto.

---

## 2. Mapa de Arquivos

| Arquivo | Papel no Pipeline |
| :--- | :--- |
| [`docs/pitch/AGENTS.md`](AGENTS.md) | Este manual operacional de regras, arquitetura, design system e build. |
| [`docs/pitch/index.html`](index.html) | Apresentação web autônoma (10 slides / 26 etapas + `BEAT_META` com `label`, `notes` e `duration`). |
| [`docs/pitch/EVIDENCIAS_E_METODOLOGIA.md`](EVIDENCIAS_E_METODOLOGIA.md) | Base empírica oficial com as 10 fontes verificadas (URLs ativas, estudos de jogos e produtividade de software). |
| [`docs/pitch/assets/`](assets) | Retratos da persona Lucas em PNG (`persona-flow.png`, `persona-shipping.png`, `persona-overwhelmed.png`). |
| [`scripts/pitch-storyboard.mjs`](../../scripts/pitch-storyboard.mjs) | Renderizador SVG puro das 26 etapas (`BEATS` 0..25 e `renderBeat(beatIdx, t)`). |
| [`scripts/pitch-pptx.mjs`](../../scripts/pitch-pptx.mjs) | Exportador AST SVG → OpenXML (`docs/pitch/exoforge-pitch.pptx`) + conversão automática para PDF via LibreOffice headless. |
| [`scripts/pitch-video.mjs`](../../scripts/pitch-video.mjs) | Orquestrador do vídeo animado (`docs/pitch/exoforge-pitch.mp4`). |
| [`scripts/pitch-encoder-c.mjs`](../../scripts/pitch-encoder-c.mjs) | Encoder C inline (`VideoToolbox` / `AVFoundation` H.264) consumido por `pitch-video.mjs`. |

### Saídas Compiladas
- [`docs/pitch/exoforge-pitch.pptx`](exoforge-pitch.pptx) — 26 slides editáveis + 26 `notesSlides` + relações externas auditadas (`hlinkClick`).
- [`docs/pitch/exoforge-pitch.pdf`](exoforge-pitch.pdf) — 26 páginas exportadas pelo LibreOffice (`impress_pdf_Export`), usadas para distribuição e auditoria visual.
- [`docs/pitch/exoforge-pitch.mp4`](exoforge-pitch.mp4) — Vídeo `1280x720`, `15 FPS`, H.264 Baseline MP4.

---

## 3. Estrutura Narrativa (3 Atos + Apêndice · 10 Slides · 26 Etapas)

A narrativa segue uma ordem intencional em **3 Atos + Apêndice** ancorada na persona **Lucas** (desenvolvedor de gameplay em time indie de 8 pessoas lançando a feature *Comprar Espada Lendária · 500 Ouro*):

| Slide | Etapas (`BEATS` 0-based) | Ato & Título | O que mostra |
| :--- | :--- | :--- | :--- |
| **Slide 1** | `0–1` (2 etapas) | **ATO I · O Pedido do Design & Fluxo Familiar na Unity** | **Beat 0 (Etapa 1)**: O pedido do Game Design (*Comprar Espada Lendária · 500 Ouro*) no contexto criativo de Lucas (desenvolvedor de gameplay em time indie de 8 pessoas sem equipe de infraestrutura). 3 requisitos de regra pura em fluxogramas: validar saldo de 500 Ouro, descontar ouro e entregar espada, notificar jogador. Na máquina local, parece tarefa de 1 tarde (~2h).<br>**Beat 1 (Etapa 2)**: *No contexto que o dev domina (Unity & C#), o início é tranquilo*: 1. Cena pronta na Unity (interface da loja e botão Comprar), 2. Código C# familiar (struct simples de inventário e função direta em C# 9), 3. Meta de 1 tarde (~2h) no computador local. Gancho dramático inferior: *"Mas o jogo é online — e a compra precisa valer no servidor para todos os jogadores."* |
| **Slide 2** | `2–4` (3 etapas) | **ATO I · A Regra do Jogo (Fluxograma & Margens)** | **Fluxograma visual vertical do Código Nobre em 3 passos com delimitação clara de responsabilidades**: *1. Jogador Clica "Comprar"* (Entrada: Espada Lendária · 500 Ouro · Cliente Unity) → *2. Saldo ≥ 500 Ouro?* (Fronteira: Regra do Jogo ↔ Validação no Servidor, com branch de recusa) → *3. Desconta 500 Ouro · Entrega Espada* (**ENTREGA** com divisão explícita de responsabilidades e margens cliente/servidor em pílulas internas: *Salvo no Inventário* [Responsabilidade do Servidor - Banco] e *Jogador Notificado* [Resposta ao Cliente - Unity]). Faixa inferior: *"A regra é simples, mas validar saldo e salvar inventário já cruza a margem entre jogo e servidor."* A regra pura no C#/Unity vem **antes** da dor técnica para fixar primeiro o valor central do estúdio, preservando o estado de fluxo contínuo (*DevEx*, ACM Queue 2023) e evitando resíduo de atenção (Leroy, 2009). |
| **Slide 3** | `5–9` (5 etapas) | **ATO II · Onde o Tempo Vaza (Os 4 Papéis Extras)** | Medidor progressivo de sobrecarga de infraestrutura (`0% → 25% → 50% → 75% → 100%`) ancorado em Mark et al. (ACM CHI 2005: 25m26s para retomar tarefa) e Parnin & Rugaber (2011: só 10% retomam em <1 min). Grade 2×2 dos **4 papéis extras** fora do jogo iluminados progressivamente (**sem nenhum placeholder de `[Slot Vazio]`**): **Papel 1 · DBA (PostgreSQL · SQL · ~45 linhas)**, **Papel 2 · Backend (REST · HTTP · JSON · ~50 linhas)**, **Papel 3 · Segurança (Auth · Anti-Cheat · ~40 linhas)** e **Papel 4 · DevOps & Nuvem (Docker · Containers · ~45 linhas)**, cada um com snippet real colorido e citação empírica. |
| **Slide 4** | `10` (1 etapa) | **ATO II · O Custo Real (Contextualização & Evidências)** | **Coluna Esquerda**: Card consolidado com a soma dos 4 papéis fora do gameplay (DBA ~45 linhas, Backend ~50 linhas, Segurança ~40 linhas, DevOps ~45 linhas) com alerta destacado: *Total fora do gameplay: ~180 linhas em 4 camadas técnicas*.<br>**Coluna Direita**: Barra de proporção empírica — **~21 linhas de Jogo (10%) vs. ~180 linhas de Infraestrutura (90% fora do gameplay)** + **2 cartões de evidências focados em jogos com contextualização clara**: *Unity Gaming Report (2024 · Estúdios Globais)* (ciclos médios subindo +39% de `218 → 304 dias`; `68%` criam multiplayer e `37%` travam integrando ferramentas externas) e *Politowski et al. (2021 · Estudo Acadêmico)* (`927` problemas de produção e sobrecarga técnica catalogados em `200` postmortems reais de jogos entre 1997–2019). Faixa inferior consolidando: *"Uma feature de 1 tarde na Unity vira semanas mantendo 4 camadas de servidor."* |
| **Slide 5** | `11` (1 etapa) | **ATO III · Da Unity para a Nuvem (1/2) — Unity Editor** | **Sem sair da Unity**: 1 clique para iniciar o serviço online direto no Editor, preservando o fluxo nativo. Janela inteira do Unity Editor (`MyFantasyRPG — LojaUI.unity — Unity 6`) com Topbar (`▶ ⏸ ⏭`, `Layers`, `Layout: Exoforge`), coluna Hierarchy (`LojaUI`, `Main Camera`, `Directional Light`, `Canvas`, `LojaPanel`, `BtnComprarEspada`), Game View com o mockup da **Loja do Ferreiro** (`OURO: 1.250`, `NÍVEL 12`, item em destaque **Espada Lendária**, `Dano +45 · Raridade Épica`, botão **`COMPRAR · 500 OURO`**), barra inferior Project/Assets (`Assets /`, `Scenes /`, `Scripts /`, `Exoforge / Extensions`), coluna lateral Exoforge Studio (`● Cluster Conectado`, `player_profile`, `match_events`, botão destacado **`+ New Extension`** com badge `CLIQUE AQUI`) e os 2 toasts flutuantes compactos sobre a base da coluna direita (*100% dentro da Unity* e *1 clique em + New Extension*). |
| **Slide 6** | `12` (1 etapa) | **ATO III · Da Unity para a Nuvem (2/2) — Popup Template** | **Geração imediata do serviço via template**: Fundo escurecido da janela inteira do Unity Editor (`opacity: 0.28`), com o modal centralizado *Create New Extension* preenchendo Extension Name (`loja_itens`), seleção do template recomendado **Persistent Data (Resource & DB)** (*"Gera serviço com [ExoResource] e banco transacional em C#"*), opções compactas (`Basic Service`, `Config & State`, `Event Producer`), botão de ação primária `⚡ Create Extension`, card de confirmação de geração de `LojaDeItens.cs` na Unity sem Docker nem YAML e os 2 toasts flutuantes compactos abaixo do modal (*Template Persistent Data → Banco e API já prontos* e *Gera LojaDeItens.cs na Unity*). |
| **Slide 7** | `13–18` (6 etapas) | **ATO III · A Solução em C# (`LojaDeItens.cs` · 21 Linhas)** | Código completo **`LojaDeItens.cs` em 21 linhas válidas em C# 9 padrão Unity com Exoforge SDK**, conectado por um **corredor de setas de `75px`** a 5 cartões explicativos empilhados sem jargões técnicos: `[ExoService("loja_itens")]` (linha 1 → *Elimina Papel DevOps* · Publicação na Nuvem em 1 Clique), `[ExoAction(Scope = "player")]` com nome inferido (linha 4 → *Elimina Papel Backend* · Conexão Automática com a Unity), `Scope = "player"` (linha 4 → *Elimina Papel Segurança* · Proteção Anti-Cheat por Padrão; Irdeto/Forbes: 77% largam cheats), corpo linhas 7–12 (`inv.Ouro -= 500; inv.Itens.Add("espada_lendaria");` → *Código Nobre em C# 9* · Foco 100% no Gameplay; Code Red 2022: código enxuto só no jogo evita 15x mais bugs e +124% de atraso; apenas a regra do ouro e da espada, resto gerenciado pelo Exoforge) e `[ExoResource]` sobre `public struct Inventario` em múltiplas linhas (linhas 15–21 → *Elimina Papel DBA* · Persistência Segura Sem SQL em banco transacional). |
| **Slide 8** | `19–22` (4 etapas) | **ATO III · Operação Gerenciada pelo Exoforge** | 4 pilares operacionais revelados progressivamente com infraestrutura pronta desde o Dia 1: **Painel Ao Vivo (Producer Studio)** para game designers consultarem itens e saldos sem painel interno (*Team Topologies*, 2019), **Tabela de Logs em Fluxo & Replay** seguindo o fluxo do jogador com reexecução em 1 clique (*DevEx*, ACM Queue 2023), **Grafo de Escalabilidade Automática** (`100 → 100 mil+ online ✓` vs. servidor comum caindo no pico; *Unity Gaming Report*, 2024) e **Atualização Sem Derrubar Quem Joga** (*Tempo de Upload `< 1 seg`* vs. horas; *Tempo Fora do Ar `0s · Ninguém cai`* vs. derrubar partidas; *Tornhill & Borg / Code Red*, 2022). |
| **Slide 9** | `23–24` (2 etapas) | **ATO III · Impacto no Negócio (Placar Executivo)** | **Beat 23**: Placar executivo honesto e defensável: **Jeito Tradicional (`Dias a Semanas` · `~180 linhas` em 4 camadas · 4 papéis · 15x mais bugs e +124% de atraso por Code Red 2022)** vs. **Com Exoforge (`No Mesmo Dia` · `21 linhas` em 1 arquivo C# na Unity · 89% menos código · upload `< 1s` sem downtime · Equipe extra de infra: Zero)**, respaldado pelo case *Triangle Factory* no Unity Gaming Report (2024) ("de semanas para dias"), Tornhill & Borg (Code Red 2022: código enxuto no jogo + infra em plataforma evitam +124% de atraso e 15x mais bugs) e Team Topologies (2019).<br>**Beat 24**: Banner executivo final com portrait de Lucas entregando o jogo (*EXOFORGE — Você descreve a sua ideia. Nós forjamos o resto.*) e os 3 selos executivos: *Escala Automática*, *Zero Tempo Fora do Ar* e *Devs de Infra: Zero*. |
| **Slide 10** | `25` (1 etapa) | **Apêndice · Bibliografia & Fontes Verificáveis** | **10 cartões estruturados com links clicáveis e auditados** (5 Relatórios de Indústria/Jogos + 5 Artigos Científicos e Engenharia), espelhando integralmente a base documentada em `EVIDENCIAS_E_METODOLOGIA.md`. |

---

## 4. Regras Visuais de Layout, Alinhamento Vertical e Storyboard

Para manter paridade estética exata entre o deck web (`index.html`), o storyboard SVG (`pitch-storyboard.mjs`), a exportação PowerPoint (`pitch-pptx.mjs`) e o PDF final via LibreOffice, siga rigorosamente estas regras:

### 4.1 Alinhamento Vertical com `pillTextY`
No renderizador SVG (`scripts/pitch-storyboard.mjs`), todo texto de linha única contido dentro de um retângulo (badges, pílulas de status, barras de proporção, cabeçalhos de tabela) **deve** usar a função de cálculo de linha de base `pillTextY`:
```javascript
function pillTextY(y, h, fontSize) {
  return Math.round((y + h / 2 + fontSize * 0.36) * 10) / 10;
}
```
O multiplicador `0.36` compensa a altura de x e as ascendentes das fontes sans-serif modernas, garantindo que o texto SVG fique perfeitamente centralizado verticalmente dentro do box visual.

### 4.2 Travamento Vertical no Conversor OpenXML (`pitch-pptx.mjs`)
No exportador PPTX (`scripts/pitch-pptx.mjs`), a lista `this.rects` registra a posição de cada retângulo renderizado. Ao emitir uma caixa de texto OpenXML:
1. Retângulos com altura `<= 34px` (`isSmallPillOrBar = r.h <= 34`) ou textos centralizados (`anchor === "middle"`) são detectados automaticamente pelo bounding box.
2. A caixa de texto é travada diretamente nas dimensões verticais do retângulo delimitador (`bh = enclosingRect.h; finalBy = enclosingRect.y`).
3. Isso garante que o PowerPoint e o LibreOffice apliquem `anchor="ctr"` dentro da mesma altura exata da pílula/badge, eliminando qualquer desalinhamento ou "texto caído" no PDF.

### 4.3 Remoção Absoluta de Placeholders (`[Slot Vazio]`)
- **Proibição estrita de placeholders de rascunho**: nas etapas progressivas do Slide 3 (`beats 5..9`), slots que ainda não foram revelados **não devem** renderizar caixas com textos como `[Slot Vazio · PAPEL X]`.
- Elementos não revelados devem permanecer ocultos ou ausentes da árvore de renderização. O deck deve apresentar apenas elementos finais limpos em todos os momentos, preservando a seriedade executiva em eventuais pausas ou impressões de página.

### 4.4 Corredor de Conectores de `75px` no Slide 7
No Slide 7 (`beats 13..18`), o painel de código à esquerda (`LojaDeItens.cs`) e os 5 cartões explicativos à direita são separados por um **corredor dedicado de `75px`** de largura. Esse espaço acomoda os conectores monocromáticos com extremidades em seta (`<polygon>`), garantindo que:
- Nenhuma linha de conexão cruze sobre outra linha;
- As pontas das setas toquem com exatidão a borda esquerda de cada cartão;
- Nenhum texto ou número de linha de código seja obstruído pelos marcadores.

---

## 5. Regras de Conteúdo, Código e Evidências

1. **Terminologia de negócio para público investidor**:
   - Usar sempre **"papel" / "papéis"** ao se referir às atribuições acumuladas (nunca "chapéu").
   - Usar **"Operação de infra gerenciada pelo Exoforge"** em vez de jargões técnicos de infraestrutura.
   - **Não** usar nos slides executivos termos como `VPS`, `JWT`, `Schema`, `BEAM`, `Elixir`, `fanout` ou micro-benchmarks como `0.07 ms Tempo Real`. Conceitos operacionais devem ser comunicados por seu impacto real: *Tempo de Upload*, *Zero Tempo Fora do Ar*, *Escalabilidade Automática*.
2. **Comparativo executivo honesto e defensável no Slide 9**:
   - Utilizar **Jeito Tradicional: `Dias a Semanas` (`~180 linhas` em 4 camadas)** vs. **Com Exoforge: `No Mesmo Dia` (`21 linhas` · 89% menos código · upload `< 1s`)**.
   - Evitar qualquer afirmação inflada como "2 a 3 semanas" sem qualificação. O corte de "dias a semanas" é sustentado empiricamente pelo estudo de caso *Triangle Factory* no *Unity Gaming Report (2024)* ("de semanas para dias").
3. **Validade estrita do código C# (`LojaDeItens.cs` no Slide 7)**:
   - O snippet deve refletir **APIs reais da SDK do Exoforge** (`[ExoService]`, `[ExoAction(Scope = "player")]` com nome de ação inferido, `Exo.Database.Get<T>`, `Exo.Context.CallerPlayerId`, `ExoActionException`, `Exo.Database.Put`, `[ExoResource]`).
   - A struct `[ExoResource]` sobre `public struct Inventario` é declarada em múltiplas linhas (linhas 15–21), após o fechamento da classe `LojaDeItens`, **sem atributo `table_name`** (C# 9 / padrão Unity):
     ```csharp
     [ExoResource]
     public struct Inventario
     {
       public string Id;
       public int Ouro;
       public List<string> Itens;
     }
     ```
   - Ao alterar o código C#, sincronizar a contagem (**`21 linhas`**) no cabeçalho da janela, título e faixas de destaque.
4. **As 10 Fontes Oficiais Verificadas**:
   - Todas as citações do deck pertencem à base das 10 fontes de [`docs/pitch/EVIDENCIAS_E_METODOLOGIA.md`](EVIDENCIAS_E_METODOLOGIA.md), espelhadas integralmente no **Slide 10 (Apêndice)**:
     1. *Unity Gaming Report (2024)* (ciclos `218 → 304d`, `68%` multiplayer, case Triangle Factory)
     2. *GDC State of the Game Industry (2024)* (apenas `16%` indies operam live-service)
     3. *Irdeto Global Gaming Survey / Forbes (2018)* (`77%` abandonam com cheats, `48%` cortam gastos)
     4. *Stripe & The Harris Poll (2018)* (`17,3h/sem` ou `42%` em manutenção e dívida)
     5. *GitLab Global DevSecOps Report (2024)* (`76%–79%` fora de código novo)
     6. *Politowski et al. (2021 · 200 postmortems / 927 problemas)*
     7. *Tornhill & Borg — Code Red ('22)* (`15x` mais bugs, `+124%` atraso)
     8. *Mark, Gonzalez & Harris (CHI '05/'08)* (`25 min 26 s` retomada + estresse)
     9. *Parnin & Rugaber (2011 · 10.000 sessões)* (só `10%` retomam em `< 1 min`)
     10. *Noda et al. (DevEx '23), Leroy ('09) & Skelton & Pais ('19)*
   - Nenhuma fonte com link quebrado (404) ou desprovida de relevância direta para jogos e produtividade de software deve ser mantida.

---

## 6. Tipografia na Exportação PPTX & LibreOffice

O exportador [`scripts/pitch-pptx.mjs`](../../scripts/pitch-pptx.mjs) gera OpenXML compatível com PowerPoint, Keynote e LibreOffice Impress. **Nunca use fontes exclusivas de um único sistema operacional sem correspondência no LibreOffice**.

Configuração tipográfica obrigatória:
- **`FONT_SANS = "Liberation Sans"`**: presente nativamente no bundle do LibreOffice e metricamente equivalente a Arial/Helvetica/Segoe UI.
- **`FONT_SYMBOL = "DejaVu Sans"`**: aplicada a runs com caracteres Unicode `[★↻✓✕→↓≥]` para evitar fallback para serif.
- **`FONT_MONO = "DejaVu Sans Mono"`**: usada em todo bloco de código e URLs da bibliografia; largura idêntica a `Menlo`.
- **Preservação de indentação**: `SlideBuilder.addText` converte espaços iniciais em `\u00A0` (NBSP) e funde runs adjacentes, preservando o alinhamento de destaque de `Scope = "player"` na linha 04 do Slide 7.

---

## 7. Comandos de Build e Checklist de Verificação

Execute a partir da raiz do repositório (`/Users/alexcs/projects/exoforge`):

### 1. Exportar `.pptx` + `.pdf` (via LibreOffice)
```bash
node scripts/pitch-pptx.mjs
```
Gera [`docs/pitch/exoforge-pitch.pptx`](exoforge-pitch.pptx) e [`docs/pitch/exoforge-pitch.pdf`](exoforge-pitch.pdf).

### 2. Recompilar o Vídeo (`.mp4`)
```bash
node scripts/pitch-video.mjs
```
Atualiza [`docs/pitch/exoforge-pitch.mp4`](exoforge-pitch.mp4) (`1280x720`, `15 FPS`, `656` frames).

### 3. Checklist Pós-Alteração (Obrigatório)
1. **Sincronia**: confirmar alinhamento entre `index.html`, `pitch-storyboard.mjs`, `pitch-pptx.mjs` e `EVIDENCIAS_E_METODOLOGIA.md`.
2. **Validação OpenXML**: descompactar `exoforge-pitch.pptx` e validar com `xmllint --noout`.
3. **Auditoria de fontes**: checar `/BaseFont` de `exoforge-pitch.pdf` (apenas `LiberationSans`, `DejaVuSans`, `DejaVuSansMono`).
4. **Inspeção visual**:
   - Títulos, pílulas e badges centralizados verticalmente sem corte;
   - Snippets dos 4 papéis no Slide 3 sem texto de placeholder vazio;
   - Barra de proporção ~21 vs. ~180 linhas e dados de jogos contextualizados no Slide 4;
   - Tela inteira do Unity Editor com ênfase em `+ New Extension` e comentários separados no Slide 5;
   - Popup modal `Create New Extension` e template em foco com comentários separados no Slide 6;
   - Corredor de 75px e setas apontando com exatidão no Slide 7 (código de 21 linhas);
   - Pilares operacionais do Producer Studio no Slide 8;
   - Comparativo do Slide 9 exibindo `Dias a Semanas` vs. `No Mesmo Dia` (21 linhas, 89% menos código) e slogan;
   - URLs clicáveis e ativas no Slide 10.
