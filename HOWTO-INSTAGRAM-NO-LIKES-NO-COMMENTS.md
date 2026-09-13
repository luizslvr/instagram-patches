# Instagram sem curtidas e sem comentários — build Morphe

Objetivo: um APK do Instagram que não permite curtir nem ver comentários.
Rota escolhida: **Morphe patches** (o sucessor do ReVanced), não patch manual de smali.

---

## 1. O estado real do ecossistema (verificado)

O plano original ("ReVanced, escrevendo patch próprio") mudou de casa em março de 2026:

- `ReVanced/revanced-patches` está **morto por DMCA** — HTTP 451, takedown `2026-03-12-morpheapp.md`,
  que derrubou a rede inteira (702 repos). Disputa de GPLv3 entre MorpheApp e ReVanced.
  A org ReVanced e o `revanced-cli` seguem vivos, mas o lineage dos **patches** é outro.
- O lineage vivo é **Morphe** (`MorpheApp/morphe-patches`). Só cobre YouTube, YouTube Music e Reddit.
- Para Instagram, o projeto mantido é **`brosssh/morphe-patches`** — 18 patches de Instagram,
  alvo 439.0.0.37.89. É a base deste fork.
- Alternativa em runtime: **InstaEclipse** (módulo Xposed/LSPosed, `disableComments`,
  `disableDoubleTapLike`). Precisa de root/LSPosed, então não serve para "APK modificado".

## 2. Decisão de engenharia: por que por rede, e não por UI

Comentários e curtidas no Instagram são **dirigidos pelo servidor**. Em vez de caçar widgets num
layout ofuscado que muda toda semana, os patches bloqueiam os endpoints na camada de rede.

A primitiva já pronta é `blockUrl(...)` de `instagram-morphe-patches-library`, que hooka
`TigonServiceLayer.startRequest` e lança `IOException` quando a URI contém um dos substrings:

```
blockUrlBasePatch  ->  hook em TigonServiceLayer.startRequest
blockUrl("...")    ->  adiciona substrings ao Set BLOCKED_URLS
```

Referência de como o próprio Morphe resolve isso: `IGNetworkInterceptor` do InstaEclipse bloqueia
`/api/v1/media/` + `comments/` para `disableComments`, e `/api/v1/feed/timeline/` para `disableFeed`.
É exatamente o mesmo mecanismo, verificado em código publicado.

## 3. O que foi construído (este fork)

    patches/.../distractionFree/HideCommentsPatch.kt   -> bloqueia /comments/, /comment/, /comment_likes/
    patches/.../distractionFree/DisableLikePatch.kt    -> bloqueia /like/ e /unlike/
                                                          + return-void no método de curtida
    patches/.../distractionFree/HideCountsPatch.kt     -> zera os números: curtida, comentário,
                                                          compartilhamento, save, view, seguidores
    patches/.../distractionFree/HideMessageBadgePatch.kt -> tira o balão de não lidas do ícone
                                                          do Direct
    tools/verify_anchors.py                            -> confere os anchors de string no APK
    tools/dump_network_endpoints.sh                    -> lista os endpoints compilados no APK
    tools/dump_json_keys.sh                            -> lista as chaves JSON que o parser do APK
                                                          realmente conhece
    tools/build.sh                                     -> pre-flight (Java, token, anchors,
                                                          endpoints, chaves) e só então compila

## 3.1 Hide counts: por que por JSON e não por UI

Os números não são widgets: são campos da resposta. A lib do brosssh traz
`JsonParserFingerprint(key)` + `replaceJsonFieldWithBogus()`, que troca a chave do JSON por "BOGUS"
no parser. O campo nunca é populado, então o número não tem o que renderizar. Chave desconhecida o
parser ignora, logo não há efeito colateral no resto do payload.

O patch tem três opções: contagens de post/reel (curtida, comentário, compartilhamento, save,
play/view), contagens de perfil (seguidores, seguindo, posts) e contagens de mensagem não lida.
As duas primeiras ligadas por padrão; a de mensagens desligada, porque os nomes de campo do inbox
são os menos certos.

**Nada disso foi verificado contra o APK alvo**, porque o APK não está aqui. Antes de confiar:

    bash tools/dump_json_keys.sh Instagram.apk            # as chaves do patch existem?
    bash tools/dump_json_keys.sh Instagram.apk --all-counts   # que OUTRAS chaves _count existem?

O segundo comando é o importante: ele lista todo token terminando em `_count`, inclusive os que o
patch não cobre (`comment_like_count`, `video_view_count` e afins aparecem nessa lista). Ajuste as
listas no `HideCountsPatch.kt` com o que aparecer.

## 3.2 Hide message badge: o balão do Direct

O balão vermelho de não lidas no ícone do Direct **não** vem de payload de mídia: vem do documento
do inbox (`/api/v1/direct_v2/inbox/`), que traz uma contagem agregada e uma por conversa. Por isso
é patch separado — alavanca e payload diferentes.

Mesma técnica de JSON: as chaves de contagem viram "BOGUS" e o parser não popula o número, então não
há o que renderizar no badge. As conversas em si não são tocadas; bloquear um campo não é bloquear o
endpoint, e o patch não mexe na lista de mensagens nem nos endpoints de mensagem.

    bash tools/dump_json_keys.sh Instagram.apk badge

Esse é o lever **menos certo** do bundle, por duas razões, e ambas estão documentadas no cabeçalho
do patch:

1. Os nomes de campo derivam mais aqui que no payload de mídia. O comando acima mostra como esta
   build escreve de fato; no teste ele já expôs `unseen_count_incl_spam`, `thread_unseen_count` e
   `unread_message_count` como candidatos não cobertos.
2. Em algumas builds o badge também é atualizado por push em tempo real, não só pela resposta do
   inbox. Se o balão sobreviver a este patch, a contagem está chegando por push, e a correção é
   fingerprintar o setter do badge — o que não dá para localizar sem o APK alvo. Quando o APK
   chegar, esse segundo lever entra no mesmo arquivo.

Os patches se registram sozinhos: o plugin `app.morphe.patches` varre os `val xxxPatch` de
topo. Não há lista manual a editar.

## 4. O que NÃO dá para fazer (e por que)

**Não existe "esconder o ícone do coração".** Nenhum projeto mantido entrega isso — nem brosssh,
nem InstaEclipse, nem instasave. Todos param em desabilitar a *ação*, nunca o *widget*. O coração
faz parte da árvore de views ofuscada do Instagram, reconstruída a cada release; fingerprintar a
view e forçar `GONE` quebraria em praticamente toda atualização. O durável é matar a ação e
esconder a contagem de curtidas.

Isso está documentado no cabeçalho do `DisableLikePatch.kt`, para não virar dívida silenciosa.

## 5. Bloqueios para terminar (preciso de você)

1. **PAT do GitHub com `read:packages`.** O build falha hoje:
   `Plugin [id: 'app.morphe.patches', version: '1.3.4'] was not found`.
   O registry `maven.pkg.github.com/MorpheApp/registry` exige o escopo. O token atual tem só
   `repo, workflow`. Criar em https://github.com/settings/tokens/new?scopes=read:packages e pôr em
   `~/.gradle/gradle.properties` (ou em `GITHUB_ACTOR`/`GITHUB_TOKEN`).

2. **O APK do Instagram** na versão 439.0.0.37.89, arm64-v8a (versionCode 384510827), de
   apkmirror.com ou uptodown.com. É o original, sem modificar — o Morphe recebe ele e emite o
   patcheado. Não preciso distribuir nada; só usar o seu arquivo.

## 6. Verificação: já foi feita, contra o Instagram 446

Os anchors foram escritos a partir de código-fonte publicado da comunidade. Depois foram
**conferidos contra um APK real**, baixado via apkcombo:

    com.instagram.android  446.0.0.49.77  (versionCode 385211303)  base.apk 136 MB, 21 dex

Resultado (13/09/2026):

| item | resultado |
|---|---|
| `double_tap_on_liked`, `used_double_tap` (método da curtida) | presentes |
| `Is ad pod`, `enable_media_notes_production`, `InstagramAppShell` | presentes |
| `/comments/`, `/comment/`, `/comment_like/`, `/like/`, `/unlike/` | presentes |
| 11 chaves de contagem (like, comment, repost, reshare, share, play, view, save, follower, following, media) | todas presentes |
| 3 chaves do badge (unseen_count, unread_count, pending_requests_total) | todas presentes |

**Um bug real foi encontrado e corrigido por isso.** O patch de comentários bloqueava
`/comment_likes/` (plural) — que **não existe** no dex. O literal correto é `/comment_like/`
(singular). Sem essa verificação o patch teria compilado e silenciosamente não bloqueado nada.

Dois pontos de honestidade sobre o resultado:

1. Verificado na **446**, não na 439 fixada. A 439.0.0.37.89 não é mais obtível em nenhum espelho
   gratuito (apkmirror e apkpure bloqueiam com 403; uptodown usa Cloudflare Turnstile; só restam
   443/444/446/447). Ou seja: os anchors sobreviveram 7 versões além da fixada, o que é um bom
   sinal, mas a 439 continua sendo o alvo declarado e não foi testada.
2. O relatório acusa **1472** outros tokens `_count` não cobertos. A esmagadora maioria é contador
   de telemetria/analytics (ex.: `audio_xl_audio_stuck_count`), não número exibido na tela. A lista
   completa fica em `build-reports/candidates-uncovered.txt` para garimpar os que importam.

### 6.1 Alvo: 439 mantida, 446 adicionada como experimental

`Constants.kt` agora declara dois alvos:

- `439.0.0.37.89` — o alvo original, com o mapa de versionCode por ABI que o brosssh validou.
- `446.0.0.49.77` — **experimental**, sem `versionCodes`. Existe porque a 439 não é mais obtível e
  ninguém novo conseguiria sequer instalar o resultado.

Marcada experimental de propósito, e a distinção importa: os quatro patches deste fork tiveram
anchors e chaves conferidos na 446, mas os patches do upstream **não**. O Morphe falha de forma
ruidosa quando um fingerprint não resolve, nomeando qual foi — então a própria tentativa de build é
a verificação dos upstream.

`versionCodes` foi omitido de propósito: o mapeamento ABI→versionCode da 446 não foi confirmado
aqui, e um mapa errado rejeitaria o arquivo correto. O bundle inspecionado (versionCode 385211303)
traz splits de densidade e **nenhum** split de ABI — pode ser que a 446 não seja dividida por ABI
como a 439 era.

Roda tudo de uma vez com o script de pre-flight. Ele confere Java 21, o token do GitHub Packages,
os anchors, os endpoints e as chaves JSON — e **só compila se tudo passar**:

    tools/build.sh Instagram.apk --check-only   # só os checks, sem compilar (pre-flight)
    tools/build.sh Instagram.apk               # checks + build do .mpp
    tools/build.sh Instagram.apk --patch       # + gera o instagram-patched.apk
    tools/build.sh Instagram.apk --install     # + instala num device conectado
    tools/build.sh Instagram.apk --force       # compila mesmo com check falhando (ciente do custo)

Os relatórios ficam em `build-reports/` (`anchors.txt`, `endpoints.txt`, `keys-counts.txt`,
`keys-badge.txt`, `keys-all.txt`), para consultar depois sem re-rodar.

Se algum check falhar, ajuste a lista no patch correspondente (`HideCountsPatch.kt`,
`HideMessageBadgePatch.kt`, `HideCommentsPatch.kt`, `DisableLikePatch.kt`) e rode de novo. O que não
dá para resolver por lista é o balão de mensagens via push — ver seção 3.2.

O equivalente manual, se preferir passo a passo:

    python3 tools/verify_anchors.py Instagram.apk
    bash tools/dump_network_endpoints.sh Instagram.apk
    bash tools/dump_json_keys.sh Instagram.apk --all-counts
    bash tools/dump_json_keys.sh Instagram.apk badge
    ./gradlew buildAndroid

## 7. Risco

- **Ban de conta.** Cliente modificado é detectável pela Meta. Use numa conta descartável até
  confirmar que está estável.
- **Não distribua o APK modificado.** Uso pessoal é zona cinzenta; redistribuir o app modificado é
  violação de copyright. O `README` do brosssh traz o `CloneInstagramPatch`, que muda o pacote para
  instalar lado a lado com o oficial — útil justamente para não mexer na sua instalação real.
- **O patch acompanha a versão.** Fixado em 439.0.0.37.89. Uma versão nova exige reconferir os
  anchors; o `verify_anchors.py` existe para tornar isso barato.
