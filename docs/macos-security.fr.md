# Pourquoi macOS vous demande de confirmer avant d'ouvrir Film Grain

[English version →](macos-security.md) · [← Retour au README](../README.fr.md)

**En bref.** macOS avertit pour toute application qui ne vient pas de l'App
Store et qui n'est pas **signée avec un Developer ID Apple** puis **vérifiée
par Apple** (cette vérification s'appelle la *notarisation*). Film Grain n'est
ni l'un ni l'autre : macOS ne peut donc pas savoir qui l'a faite, ni si Apple
l'a examinée. **C'est tout ce que dit l'avertissement.** Ce n'est pas un
jugement sur ce que fait l'application.

C'est aussi, en toute honnêteté, une bonne raison de ne pas me croire sur
parole. Cette page explique donc ce qui se passe, puis vous montre trois façons
de vérifier par vous-même, ou d'éviter l'avertissement.

---

## Ce qui se passe

Quand vous téléchargez un fichier avec un navigateur, macOS le marque
*« téléchargé depuis Internet »* (un marqueur caché appelé **quarantaine**). À la
première ouverture d'une application marquée, un contrôle intégré, **Gatekeeper**,
cherche deux choses :

1. **Une signature d'un Developer ID Apple.** Apple délivre ce certificat aux
   développeurs inscrits (l'Apple Developer Program, aujourd'hui environ
   99 dollars US par an). Il dit : *« cette application a été faite par ce
   développeur et n'a pas été modifiée depuis. »*
2. **La notarisation.** Le développeur envoie l'application à Apple, qui la
   passe automatiquement au crible à la recherche de logiciels malveillants
   connus et note qu'elle a réussi le contrôle.

Film Grain n'a **ni l'une ni l'autre**. Ce projet n'utilise pas de Developer ID.

Il a en revanche une signature **« ad hoc »** : une signature sans identité
derrière. Les Mac Apple Silicon exigent *une* signature avant d'exécuter
n'importe quel code ; la fabrication de l'application en ajoute donc une — mais
elle ne prouve rien sur l'auteur. Vous pouvez le constater sur votre propre
exemplaire :

```
codesign -dv --verbose=2 "/Applications/Film Grain.app" 2>&1 | grep -E "Signature|TeamIdentifier"
```

Elle affiche `Signature=adhoc` et `TeamIdentifier=not set`. Et le verdict de
Gatekeeper lui-même :

```
spctl --assess --type execute -vv "/Applications/Film Grain.app"
```

répond `rejected` — ce qui, pour une application téléchargée, est simplement la
façon qu'a Gatekeeper de dire *« je ne peux pas me porter garant de celle-ci »*.
(Une application que vous fabriquez vous-même n'est jamais marquée comme
téléchargée : macOS ne pose alors aucune question. Voir la solution 3.)

## Est-ce sûr ?

L'avertissement ne peut pas vous le dire, et son absence sur d'autres
applications ne vous le dit pas non plus. Plutôt que de me faire confiance, vous
pouvez :

- **Lire le code source.** Il est entièrement dans [`source/`](../source) :
  environ 1 000 lignes de Swift réparties en trois fichiers, plus le script de
  fabrication. Il n'y a **aucun code réseau** (l'application ne se connecte à
  rien), elle **ne lance aucun autre programme**, et elle n'utilise **aucun code
  tiers** — seulement ce que macOS fournit.
- **Vérifier que votre téléchargement est bien le fichier publié.** Les notes de
  la version donnent son empreinte SHA-256. Après le téléchargement, dans le
  Terminal :

  ```
  shasum -a 256 ~/Downloads/Film-Grain-0.3-macos-arm64.zip
  ```

  Les deux valeurs doivent être identiques.
- **La fabriquer vous-même** — voir la solution 3.

## Trois façons de continuer

### 1. L'ouvrir quand même (une seule fois)

**Sous macOS 15 (Sequoia) et plus récent, macOS 26 compris :**

1. Double-cliquez sur *Film Grain*. Un message indique qu'Apple n'a pas pu
   vérifier qu'elle ne contient pas de logiciel malveillant. Cliquez sur
   **Terminé** — *pas* sur « Placer dans la corbeille ».
2. Ouvrez **Réglages Système → Confidentialité et sécurité** et descendez
   jusqu'à la section **Sécurité**. Elle indique que *« Film Grain » a été
   bloquée pour protéger votre Mac*, avec un bouton **Ouvrir quand même**.
   Cliquez dessus et confirmez avec votre mot de passe ou Touch ID.
3. macOS demande une dernière fois. Cliquez sur **Ouvrir**.

Ensuite elle s'ouvre normalement, à chaque fois.

**Sous macOS 14 (Sonoma) :** clic droit (ou Contrôle-clic) sur *Film Grain*,
**Ouvrir**, puis **Ouvrir** de nouveau.

> Le texte exact de ces messages change un peu selon la version de macOS et la
> langue. Le chemin — Réglages Système → Confidentialité et sécurité → Ouvrir
> quand même — est celui qu'Apple documente.

### 2. Retirer vous-même le marqueur « téléchargé »

Si vous êtes à l'aise avec le Terminal, cette commande supprime le marqueur de
quarantaine, et macOS cesse de demander. Adaptez le chemin à l'endroit où vous
avez mis l'application :

```
xattr -dr com.apple.quarantine "/Applications/Film Grain.app"
```

Ne le faites que pour une application dont vous avez regardé le code ou dont
vous faites confiance à l'auteur : cela désactive justement le contrôle dont
parle cette page.

### 3. La fabriquer vous-même — aucun avertissement

Une application que vous fabriquez sur votre propre Mac n'a jamais été
téléchargée, elle n'est donc jamais marquée, et macOS n'a rien à demander. Il
faut les outils en ligne de commande d'Apple (pas Xcode en entier), puis trois
commandes — elles sont dans le
[README](../README.fr.md#-lobtenir--deux-façons). Cela prend quelques secondes
et, en prime, vous avez lu ce que vous lancez.

---

## Pourquoi ne pas simplement la signer correctement ?

Parce que cela supposerait de s'inscrire au programme développeur payant d'Apple
et de lui soumettre chaque version, pour un petit outil gratuit. Si cela change,
cette page le dira. D'ici là : le code source est ici, l'empreinte est dans les
notes de la version, et la fabriquer soi-même reste toujours possible.
