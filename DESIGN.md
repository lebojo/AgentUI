---
name: AgentUI
description: Un espace de travail natif macOS pour organiser projets, worktrees et terminaux.
---

# Design System: AgentUI

## Overview

**Creative North Star: "L’espace de travail natif"**

Une interface compacte inspirée de la hiérarchie Orca, avec les conventions de navigation de macOS. La barre latérale organise le travail ; le terminal interactif occupe le centre et un inspecteur natif repliable donne accès au contexte du worktree sélectionné. La précision des libellés, la sélection native et les actions contextuelles portent l’identité.

**Key Characteristics:**

- Hiérarchie explicite, densité compacte et terminal au premier plan.
- Contrôles SwiftUI, SF Symbols et couleurs sémantiques du système.
- Libellés français directs, chemins et états accessibles sans surcharge.

Documentation extraite de `AgentUI/ContentView.swift`, `AgentUI/Views/`, `AgentUI/Services/TerminalSessions.swift` et `AgentUI/MyApp.swift`. Les captures ont été écartées : Stage Manager et la capture AppKit ont altéré la composition ou la vibrance et les couleurs (voir `.impeccable/review/REVIEW.md`). Ce document décrit le code ; il ne constitue pas une validation visuelle.

## Colors

La palette appartient à macOS et suit son apparence. Conserver les références sémantiques natives ; aucune valeur hexadécimale fixe ne les remplace.

- **Accent système** : boutons `.borderedProminent` et sélection native de la liste.
- **Surface du terminal** : `NSColor.textBackgroundColor`, aussi utilisé derrière l’accueil et le détail ; texte du terminal en `NSColor.textColor`.
- **Texte secondaire** : `.secondary` pour icônes de contexte, chemins, compteurs et aides ; `.tertiary` pour le chevron du fil de contexte.
- **Filtre** : `.quaternary.opacity(0.6)` pour son fond discret.
- **États** : `.green` pour un processus terminal ouvert ou un check réussi, `.secondary` pour une session terminée ou un projet en veille, `.red` pour les erreurs du formulaire et les checks échoués, `.orange` pour les checks en cours ou en attente. Les checks associent couleur, symbole et texte. Les messages de récupération utilisent le matériau `.bar`.

**The Semantic Color Rule.** Garder les couleurs sémantiques et les états natifs ; une capture de leur apparence ne définit pas une palette permanente.

## Typography

Police système macOS pour l’interface ; police système monospace régulière (13 pt) pour SwiftTerm. Les lignes ordinaires de la liste héritent de la typographie native, sans taille globale forcée.

- Accueil : titre semi-gras (22 pt), texte explicatif (13 pt).
- Filtre, fil de contexte et actions discrètes : police système (12 pt).
- Chemin, pied de barre latérale et petites aides : police système (11 pt) ; compteurs de dossiers en `.caption` avec chiffres à chasse fixe.
- Formulaires : titre `.title3` semi-gras, texte et erreurs `.callout`, progression `.caption`.
- Inspecteur : titres `.headline`, contenu `.callout`, métadonnées `.caption` ; aperçus de texte et de diff en police système monospace (12 pt).

Conserver la troncature des noms sur une ligne et les chemins complets dans les aides contextuelles. Le chemin du détail est sélectionnable et tronqué au milieu.

## Layout

`NavigationSplitView` à deux colonnes, style `.balanced`, avec barre d’outils unifiée. Fenêtre initiale (1180 × 760 pt), minimum (760 × 480 pt). Barre latérale redimensionnable : minimum (240 pt), largeur idéale (285 pt), maximum (420 pt).

La `List(.sidebar)` contient des `DisclosureGroup` : dossiers virtuels → projets → terminaux principaux et worktrees supplémentaires → terminaux. Les terminaux du worktree principal apparaissent directement sous leur projet. Les projets sans dossier restent à la racine. L’en-tête « Projets » contient le menu d’ajout +, au-dessus du filtre. Le filtre précède la liste ; les compteurs de terminaux la suivent.

Le détail empile un fil de contexte projet / worktree (40 pt), le terminal extensible et une barre de chemin (29 pt). Le terminal AppKit garde des marges de 12 pt à gauche, 8 pt à droite et en bas, 10 pt en haut. Les séparateurs natifs distinguent les bandes de contexte.

À droite, `.inspector` conserve la présentation native et une largeur de 260–440 pt (310 pt idéale). Le bouton `sidebar.right` le masque ou le montre ; visibilité et onglet sont mémorisés. Un `Picker(.segmented)` natif à quatre symboles donne accès à Fichiers, Agents, Git et Checks. Il est placé dans un `.safeAreaInset(edge: .top)` de l’inspecteur et reste fixé sous la toolbar pendant le défilement. Le contenu suit le worktree sélectionné ; sans sélection, un état vide invite à ouvrir un terminal. Les aperçus apparaissent dans une feuille redimensionnable (minimum 560 × 360 pt, taille idéale 780 × 540 pt).

Les formulaires sont des feuilles de 440 pt de largeur, avec une marge de 24 pt et un espacement principal de 18 pt. Le redimensionnement repose sur les conteneurs natifs ; aucun breakpoint web n’est défini.

## Elevation & Depth

La profondeur vient de la fenêtre, de la barre latérale, des feuilles et des matériaux natifs. Aucun shadow personnalisé. Les séparateurs et la hiérarchie typographique structurent le contenu ; aucun effet décoratif animé n’est ajouté.

## Shapes

Contrôles et feuilles conservent leurs formes macOS. Le filtre utilise un rectangle arrondi (rayon de 7 pt) et une marge intérieure de 8 pt. Les champs des formulaires utilisent `.roundedBorder`. Les onglets de l’inspecteur utilisent un fond accentué discret et un rayon de 6 pt pour l’onglet sélectionné. Ne pas généraliser le rayon du filtre à tous les contrôles.

## Components

- **Navigation** : SF Symbols `folder`, `shippingbox`, `arrow.triangle.branch` et `terminal` distinguent les niveaux. Sélection native du terminal ; noms sur une ligne, menus contextuels et déplacement des projets vers les dossiers virtuels.
- **Ajout** : menu + dans l’en-tête de la barre latérale pour projet, import et dossier virtuel. Le plus d’un projet crée un worktree ; le plus d’un worktree et l’action du détail créent un terminal. Chaque bouton à icône porte une aide et un libellé d’accessibilité.
- **Filtre** : recherche textuelle avec effacement accessible ; les groupes se déploient pendant la recherche et un état « Aucun résultat » explique l’absence de correspondances.
- **Branche Git** : petite capsule verte en police système 10 pt, symbole de branche et nom tronqué au milieu, limitée à 100 pt dans la liste et 180 pt dans le détail. Teintes adaptées au mode clair/sombre ; nom complet dans l’aide et le libellé d’accessibilité. Pas de badge hors dépôt ; commit abrégé dans une capsule neutre pour HEAD détachée.
- **Terminal** : vue AppKit SwiftTerm réelle, focus clavier à l’ouverture. Le point vert indique uniquement un processus ouvert, jamais l’activité d’un agent. Une session terminée affiche un message et « Rouvrir le terminal ».
- **Fermeture et veille** : ⌘W ferme directement le terminal sélectionné et son processus ; sans terminal sélectionné, la commande native ferme la fenêtre. Fermer le dernier terminal conserve le projet, dont le nom passe en couleur secondaire avec le symbole `moon`. Cliquer sur son nom ouvre un terminal principal. Les feuilles et fenêtres modales gardent leur gestion native de fermeture.
- **Inspecteur Fichiers** : arborescence à chargement paresseux, dossiers avant fichiers, chemins dans les aides ; menus pour ouvrir dans l’application par défaut ou afficher dans le Finder. Les aperçus UTF-8 sont sélectionnables et en lecture seule, avec indication de la limite de taille ; les fichiers incompatibles affichent une erreur explicite.
- **Inspecteur Agents** : terminaux groupés par worktree, état textuel « À ouvrir », « Ouvert » ou « Terminé », coche sur la sélection et action Nouveau terminal. Ces états décrivent la session, pas le raisonnement d’un agent.
- **Inspecteurs Git et Checks** : changements locaux avec statut et diff en lecture seule ; liens vers le dépôt, la pull request et les exécutions GitHub. Les checks de PR et les Actions du HEAD local occupent des sections distinctes ; une note signale les commits différents. Actualisation manuelle, progression et erreurs de connexion restent visibles. Les requêtes automatiques concernent les onglets Git/Checks visibles.
- **Accueil** : symbole terminal, titre, explication courte et actions pour ajouter un projet, importer un dossier ou créer un dossier virtuel. Un dossier vide propose l’ajout d’un projet ; un worktree sans terminal propose d’en ouvrir un.
- **Formulaires** : champ nommé, focus initial, validation de saisie vide, actions Annuler / Enregistrer ou Créer. Pendant la création Git, progression visible, soumission désactivée et bouton Arrêter disponible ; une erreur reste lisible et sélectionnable dans la feuille. Une création partielle est signalée sans supprimer ses fichiers.
- **Récupération** : alertes natives pour les erreurs générales, confirmation pour la fermeture par menu contextuel et le retrait de projet, bandeau avec « Réessayer » si l’organisation enregistrée est illisible. Le mode de récupération désactive les modifications pour préserver les données.

## Do's and Don'ts

- Do conserver la hiérarchie dossier → projet → terminaux et worktrees → terminaux.
- Do privilégier les contrôles natifs, les SF Symbols et les couleurs sémantiques.
- Do maintenir le terminal comme surface principale et rendre les actions locales compréhensibles.
- Don't présenter le point vert comme une activité d’agent.
- Don't remplacer les matériaux système par des couleurs déduites des captures invalides.
- Do garder l’inspecteur repliable et lié au contexte sélectionné.
- Don't confondre les checks du HEAD distant de la PR avec les Actions du HEAD local.
- Don't ajouter d’animations décoratives à cette interface centrée sur le terminal.

## Isolation et persistance

La barre latérale, ses lignes de projet, les lignes de terminal et le pied de liste sont des vues séparées. La sélection et l’expansion sont observées indépendamment des tableaux de projets/dossiers. Le filtre est recalculé uniquement lorsque ses entrées changent. Les modifications Git utilisent un conteneur paresseux ; leurs snapshots équatables évitent des notifications identiques à chaque lecture.

Les écritures JSON sont regroupées sur 250 ms et sérialisées hors MainActor avec un numéro de révision. Un bandeau persistant affiche les erreurs d’écriture et propose Réessayer la sauvegarde. La CLI et la fermeture attendent une sauvegarde effective. L’icône de l’application est le document Icon Composer `AgentUI/AgentUI.icon` fourni par l’utilisateur.
