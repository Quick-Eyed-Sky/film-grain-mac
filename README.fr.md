# Film Grain — déposez une image, obtenez du grain argentique, sur votre Mac

**Une petite application Mac native qui ajoute du grain de pellicule, une dominante de couleur et une vignette à vos images. Déposez-les sur la fenêtre, réglez, enregistrez.**

Pas de navigateur, pas de Python, rien à installer. La force, l'échelle, la
chaleur et la vignette tiennent sur une seule page, chacune avec une phrase
claire à côté qui dit ce qu'elle fait vraiment. Rien ne sort de votre Mac.

![La fenêtre](docs/screenshot.png)

*Aperçu en direct à taille réelle, pour juger le grain là où il est vraiment.*

> Outil **non officiel**. L'effet est une réécriture en Swift du **node
> FilmGrain** de
> [ComfyUI-post-processing-nodes](https://github.com/EllangoK/ComfyUI-post-processing-nodes)
> par **EllangoK** ([le fichier d'origine](https://github.com/EllangoK/ComfyUI-post-processing-nodes/blob/master/post_processing/film_grain.py)).
> Il n'est ni fait par lui ni affilié à lui. Comme il en dérive, il est publié
> sous la même licence, **GPL-3.0** — voir
> [Licence et attribution](#-licence-et-attribution).

**[⬇️ Télécharger l'application →](https://github.com/Quick-Eyed-Sky/film-grain-mac/releases/latest)**
· **[Pourquoi macOS demande de confirmer avant de l'ouvrir →](docs/macos-security.fr.md)**
· [This README in English →](README.md)

---

## ✨ Ce que ça fait

- **Déposez une image, plusieurs, ou un dossier entier** sur la fenêtre — ou sur
  l'icône de l'application dans le Dock. Des images déposées plus tard
  remplacent les précédentes ; les fichiers qui finissent déjà par `_grain` sont
  sautés, donc on peut déposer deux fois le même dossier sans risque.
- **Aperçu en direct, et un bouton pour comparer.** Maintenez enfoncé **Hold to
  see the original**, en haut des réglages : vous voyez l'image sans aucun effet ;
  relâchez, et les effets reviennent. L'œil peut comparer avec et sans, sans
  toucher à un curseur. (L'interrupteur *Result / Original* au-dessus de l'image
  fait la même chose, mais reste là où vous l'avez mis.)
- **Rapide.** Le motif de grain est calculé une seule fois : bouger *Strength*,
  *Warmth* ou *Vignette* ne le recalcule pas, l'aperçu suit donc instantanément.
  Pour une image de 12 mégapixels, le grain prend environ 20 ms (mesuré), et
  l'aller-retour complet — lire le fichier, ajouter le grain, le réécrire avec
  ses métadonnées — environ 0,7 s.
- **Naviguez avec les flèches gauche et droite du clavier**, en boucle : après
  la dernière image vient la première.
- **Contrôlez un gros lot avec la touche virgule.** Appuyez sur `,` (elle est
  indiquée dans le menu **Pictures**, sous le nom *Random Picture*) pour passer à
  une image tirée au hasard dans votre liste. Chacune sort une fois avant qu'une
  revienne : avec 200 images, vous voyez « un peu partout » si l'effet est bon
  avant d'enregistrer quoi que ce soit.
- **Enregistre à côté de l'original** sous `nom_grain.png` (ou `.jpg`, qualité
  95). L'original n'est jamais touché, et rien n'est jamais écrasé — un nom déjà
  pris devient `nom_grain_2.png`.
- **Conserve ce qui est dans le fichier** : profil de couleur et métadonnées
  (EXIF et XMP). Pour une image faite avec Draw Things, le prompt et les
  paramètres de génération restent dans le fichier enregistré.
- **Une graine (seed)** : même graine et mêmes réglages, exactement le même
  grain. En option, un petit `.txt` à côté de chaque résultat consigne tous les
  réglages (désactivé au départ).
- **Retient vos derniers réglages**, y compris la vue (*Fit* ou *Actual size*).

## ⚠️ À savoir avant de commencer

**« Scale » ne grossit pas le grain.** C'est surprenant, et cela a été vérifié
sur le code du node d'origine : le grain fait toujours **un pixel**. Ce que
règle *Scale*, c'est **l'uniformité** du grain sur l'image — des valeurs basses
donnent des plages où il est plus fort ou plus faible, des valeurs hautes le
même grain partout. Si vous voulez un grain gros (l'aspect d'une pellicule
rapide), ce node ne le fait pas, et cette application non plus.

**Jugez le grain en *Actual size*.** *Fit* réduit l'image pour qu'elle tienne
dans la fenêtre, et une image réduite gomme le grain. Un changement de
*Strength* peut sembler presque sans effet en *Fit*, et très net en
*Actual size*.

---

## 💻 Configuration requise

- Un Mac **Apple Silicon** (M1 ou plus récent) — l'application n'est construite
  que pour lui.
- **macOS 14 (Sonoma) ou plus récent** — c'est la cible de la construction.
  L'application n'a été lancée et testée que sous macOS 26 : 14 et 15 sont la
  cible déclarée, pas un fait vérifié.

## 📥 L'obtenir — deux façons

**1. Télécharger l'application** depuis la
**[page des releases](https://github.com/Quick-Eyed-Sky/film-grain-mac/releases/latest)** :
décompressez, glissez `Film Grain.app` dans votre dossier Applications.
**macOS vous demandera de confirmer avant de l'ouvrir la première fois** — c'est
normal pour une application qui n'est pas signée avec un Developer ID Apple, cela
ne dit rien de ce que fait l'application, et
**[cette page explique exactement pourquoi et comment l'ouvrir](docs/macos-security.fr.md)**.

**2. La fabriquer vous-même, à partir du code source de ce dépôt** — et macOS ne
demandera rien, car une application construite sur votre propre Mac n'a jamais
été « téléchargée ». Il faut les outils en ligne de commande d'Apple (pas Xcode
en entier) :

```
xcode-select --install
```

puis, dans le Terminal :

```
git clone https://github.com/Quick-Eyed-Sky/film-grain-mac.git
cd film-grain-mac/source
./build_app.sh
```

Cela prend quelques secondes et met `Film Grain.app` dans le dossier
`film-grain-mac`. Rien d'autre n'est installé ni modifié sur votre Mac.

---

## 🎛️ Les réglages

Les valeurs de départ sont celles du node d'origine.

| Réglage | Ce qu'il fait |
|---|---|
| **Strength** (0–1, départ 0,20) | La visibilité du grain. 0 = aucun. |
| **Scale** (1–100, départ 10) | L'*uniformité* du grain sur l'image — **pas sa taille** (voir plus haut). |
| **Warmth** (−100 à +100, départ 0) | Dominante de couleur. Négatif = plus froid, plus bleu ; positif = plus chaud, plus orangé. |
| **Vignette** (0–1, départ 0) | Assombrit les coins. 1 = les coins deviennent noirs. |
| **Seed** | Même graine + mêmes réglages = exactement le même grain. Le dé en tire une autre. |

## 🔬 En quoi cela diffère du node d'origine

- **Une graine.** Le node tire un grain différent à chaque exécution, sans moyen
  d'en retrouver un. Ici, la graine fait partie des réglages.
- **La vignette s'arrête à 1.** Le node propose jusqu'à 10, mais au-delà de 1 il
  ne se passe rien de plus : le curseur s'arrête là où l'effet s'arrête.
- **Vitesse.** Le motif de grain est mis en cache, comme décrit plus haut.

Pour le reste, c'est le même calcul : les statistiques du grain du node (son
propre code Python, exécuté sur une vraie image) ont été comparées à celles de
cette application, pour trois valeurs de *Scale* — force du grain et variation
sur l'image — et elles concordent.

## 🧾 Limites

- Une image avec **transparence** est aplatie sur du blanc (une note le dit dans
  le `.txt`, si vous le demandez).
- Une image en **16 bits** est ramenée à 8 bits par canal.
- **Le grain ne se compresse pas.** Un PNG avec grain est bien plus gros que
  l'original : de 37 % à 174 % de plus dans les essais (une image agrandie en
  douceur grossit le plus).
- Pas de version signée ni notarisée, d'où la confirmation que demande macOS —
  voir [l'explication](docs/macos-security.fr.md).

---

## 📜 Licence et attribution

**Cette application est sous GPL-3.0** — voir [LICENSE](LICENSE) et
[NOTICE.md](NOTICE.md).

C'est une **œuvre dérivée** : le grain, la chaleur et la vignette sont une
réécriture en Swift du node `FilmGrain` de
[ComfyUI-post-processing-nodes](https://github.com/EllangoK/ComfyUI-post-processing-nodes)
par **EllangoK**, lui-même sous GPL-3.0. **C'est une adaptation modifiée, pas
l'original :** réécrite en Swift comme application Mac autonome, avec une graine,
un cache du motif de grain, une vignette limitée à ce qui a un effet, et une
fenêtre autour. Si vous la redistribuez, la GPL-3.0 s'applique aussi à vous :
gardez la licence, gardez cette mention, dites que vous l'avez modifiée, et
mettez le code source à disposition.

Elle n'utilise rien d'autre que macOS lui-même (SwiftUI, Core Graphics,
Image I/O) : il n'y a donc aucun code tiers à citer en dehors du node.

---

## 👋 Qui a fait ça

Jean-Pascal — **[Quick-Eyed Sky](https://www.youtube.com/@QuickEyedSky)** sur
YouTube, [QES](https://huggingface.co/QES) sur Hugging Face. Pas
programmeur : cela existe parce que je voulais le grain de ce node sous la forme
d'une petite application Mac à part entière.

Si cela vous a fait gagner un après-midi, vous pouvez
[m'offrir un café](https://buymeacoffee.com/oFJ5CiY7n). C'est entièrement
facultatif, et le projet reste tout aussi libre dans les deux cas.

---

## 🙏 Remerciements

À **EllangoK**, pour les
[ComfyUI-post-processing-nodes](https://github.com/EllangoK/ComfyUI-post-processing-nodes)
sur lesquels tout cela repose, et pour les avoir publiés sous une licence qui
permet aux autres d'en apprendre.
