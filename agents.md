# SCRIPT A SPELL — DOCUMENTUL SUPREM DE ARHITECTURĂ, DESIGN ȘI GHIDUL AGENTULUI (COMPLETE GDD & TECHNICAL SPECS)

Bun venit! Acest document servește ca "sursă unică de adevăr" (Single Source of Truth) pentru proiectul **Script a Spell**. El definește viziunea creativă, mecanicilor de joc, elementele de atmosferă, arhitectura tehnică pentru Godot Engine 4.x și regulile de funcționare/memorare pentru inteligența artificială (Agentul) care lucrează la codebase.

---

## 1. REZUMATUL EXECUTIV & IDENTITATEA PROIECTULUI

*   **Titlu:** Script a Spell
*   **Gen:** Co-op Sci-Fi/Medieval Panic, Rogue-lite, Quota-Game, Physics-Comedy (Friendslop).
*   **Motor Grafic:** Godot Engine 4.x (optimizat pentru multiplayer online stabil și compatibilitate MVP).
*   **Număr de Jucători:** 1–4 Jucători (Co-op online / LAN).
*   **Target Audience:** Fani ai jocurilor cooperativ-haotice (stil *Lethal Company*, *Phasmophobia*, *REPO*, *Kletka*) și publicul larg atras de comedie, interacțiuni fizice amuzante și streameri de pe TikTok/Twitch.

### Identitatea Vizuală (The Pilgrim + Witch It Contrast)
Jocul folosește un hibrid vizual unic și contrastant pentru a amplifica atât tensiunea, cât și comedia:
1.  **Lumea și Dungeon-ul (Stil Pilgrim):** Grafică low-poly, texturi hand-painted/pixelate, medii întunecate, reci, sumbre, coridoare masive de piatră luminate doar de torțe cu ulei și lămpi ruginite. Atmosferă reală de tensiune și suspans medieval.
2.  **Mecanicile și Efectele (Stil Witch It):** Elementele legate de magie și cod (interfețe, lasere, efecte de erori, transformări) explodează în culori neon (roz fosforescent, verde intens, albastru electric). Animațiile personajelor devin bouncy (elastice), fizica ragdoll este exagerată, iar efectele speciale de glitch sunt instantaneu hilare.

---

## 2. CORE GAMEPLAY LOOP (BUCLA PRINCIPALĂ DE JOC)

Jocul se desfășoară sub presiunea unei cote corporatiste (**Quota**) de adunat comori și resurse dintr-un puț infinit de dungeon-uri procedurale (**The Pit**), pe parcursul unui ciclu de zile prestabilit.

```
       +-------------------------------------------------------+
       |                  Faza de Hub / Buncăr                 |
       |  - 120 de secunde în siguranță                         |
       |  - Vânzare loot, acoperire Quota                      |
       |  - Upgrade corp, cumpărare blocuri cod / iteme        |
       +---------------------------+---------------------------+
                                   |
                                   v
       +-------------------------------------------------------+
       |                  Faza de Dungeon (Expediția)          |
       |  - Coborâre în The Pit                                |
       |  - Colectare loot, pachete de date și mana            |
       |  - Utilizare și programare scripturi pe echipament    |
       +---------------------------+---------------------------+
                                   |
                                   v
       +-------------------------------------------------------+
       |                  Faza de Haos (Erorile)               |
       |  - Cod greșit / modificat periculos în Simulation     |
       |  - Chaos Engine interceptează syntax/runtime errors   |
       |  - Declanșare pedepse fizice imprevizibile & comice    |
       +---------------------------+---------------------------+
                                   |
                                   v
       +-------------------------------------------------------+
       |                 Verificare Sfârșit Ciclu              |
       |  - Quota atinsă? -> Trecere la următoarea Quota mai grea|
       |  - Quota ratată? -> Curățare memorie (Soul Defrag)    |
       |    și resetarea completă a run-ului                   |
       +-------------------------------------------------------+
```

*   **Faza de Hub / Buncăr (120 de secunde):** Jucătorii se adună în buncărul medieval securizat. Vând loot-ul din runda anterioară pentru a acoperi Quota. Primesc 25% din quota finalizată și 100% din tot ce depășește quota (over-quota) ca fonduri proprii (aur/mana-credits). Cumpără blocuri de cod și consumabile din shop-uri și își reprogramează echipamentele sau părțile corpului.
*   **Faza de Dungeon (Expediția):** Jucătorii coboară în dungeon. Adună loot-ul și pachete de date/mana magice. Pentru a interacționa cu mediul (deschis porți, atacat monștri, fugit), ei depind de scripturile compilate pe echipamentul și corpul lor.
*   **Faza de Haos (Erorile):** Datorită grabei sau presiunii monștrilor, codul prost scris dă erori de sintaxă sau logică. Chaos Engine-ul interceptează erorile și declanșează pedepse fizice imprevizibile și comice în timp real.
*   **Moartea și Eșecul Quota:** Dacă jucătorii mor, pot fi readuși la viață dacă au programat un script de reanimare corect. Dacă la sfârșitul ciclului de zile echipa nu atinge cota, asistentul corporatist al dungeon-ului rulează o curățare a memoriei: jucătorii sunt aruncați în Recycle Bin-ul magic (*The Soul Defrag*) și run-ul este resetat.

---

## 3. ROLURILE JUCĂTORILOR & ASIMETRIA DE GAMEPLAY

### A. Operatorul (The VR Dwarf Wizard) — Opțional (Stil Lethal Company)
Un jucător poate alege să rămână în buncărul securizat, controlând de la distanță întreaga operațiune dintr-o interfață de monitorizare 360 de grade.

*   **Prezentare Vizuală:** Un pitic burtos cu o cască VR uriașă din cupru legată prin cabluri groase de un ceaun în care fierb licori magice. El stă pe un butoi de bere transformat în scaun ergonomic de gaming.
*   **Control 360:** Operatorul își rotește fizic scaunul apăsând `CTRL + A` sau `CTRL + D` pentru a naviga între ecranele din buncăr:
    1.  **Ecranul Terminalului:** O consolă text unde scrie cod text brut, editând și modificând scripturile exploratorilor de la distanță.
    2.  **Ecranul Radar/CCTV:** O vizualizare 3D de tip wireframe cu linii verzi fluorescente unde vede punctele jucătorilor și inamicilor în dungeon.
    3.  **Panoul de Management RAM:** Tuburi de sticlă umplute cu lichid magic albastru (Mana-RAM).
*   **Vulnerabilitate:** Operatorul este în siguranță în buncăr, dar dacă un monstru reușește să intre, el trebuie să își dea casca jos, moment în care conexiunea de date se taie instantaneu. El trebuie să își ia fizic măciuca și să își apere viața în mod direct.

### B. Exploratorii de pe Teren
Jucătorii care coboară fizic în dungeon pentru a căuta loot.

*   Ei au o tabletă de piatră cu ecran magic unde folosesc o interfață rapidă cu blocuri (*Scratch-like*) cu culori contrastante neon.
*   Pe teren, ei pot modifica rapid doar variabilele și string-urile (ex: viteza cizmelor, tipul de element al sabiei), neavând destul RAM sau stabilitate să schimbe structura blocurilor în timp real. Modificarea codului complex direct în simulare (In Simulation) prezintă riscuri uriașe de glitch-uri fizice din cauza Chaos Engine-ului.

---

## 4. MECANICA CENTRALĂ: RAM-LINKING (LIFE-BINDING)

Cea mai intensă mecanică a jocului, care creează o legătură strânsă de dependență și risc între Operator și exploratori:

*   **Alocarea RAM-ului:** Echipamentele avansate (senzori, arme grele, revive automat) necesită RAM pentru a rula. Operatorul este sursa principală de procesare și decide cum distribuie RAM-ul său magic (de exemplu, dă 60% din RAM unui jucător experimentat și câte 20% celorlalți doi).
*   **Life-Binding (Legătura de viață):** RAM-ul este conectat direct la sistemul nervos și viața Operatorului. Dacă un explorator moare în dungeon, terminalul Operatorului scoate scântei și explodează, iar Operatorul pierde pe loc un procentaj de viață egal cu RAM-ul alocat acelui jucător (ex: dacă cel cu 60% RAM moare, Operatorul își pierde pe loc 60% HP).
*   **Opționalitate (Jocul fără Operator):** Dacă echipa joacă fără Operator, capacitatea lor locală de RAM este minusculă, putând rula doar scripturi ultra-simple (fără logică avansată, senzori sau revive-uri automate).

---

## 5. SISTEMUL DE PROGRAMARE ȘI PERSONALIZAREA CORPULUI/LOOT-ULUI

Jucătorii au libertate creativă absolută asupra modului în care își programează personajul și inventarul:

*   **Personalizarea Corpului:** Fiecare parte a corpului poate fi programată prin intermediul socket-urilor rurice:
    *   *Capul:* Poate fi codat cu senzori termici, night-vision sau vedere la 360 de grade.
    *   *Picioarele:* Pot fi programate pentru double-jump sau sprint automat sub anumite condiții.
*   **Revive-ul Runic:** Jucătorii își pot programa propriul comportament de înviere:
    `If (Sănătate == 0) -> Run(ReviveBlock())`
    Dacă scriptul are erori de logică sau sintaxă, revive-ul poate da greș spectaculos: înviere ca zombie inamic care atacă echipa, înviere cu corpul inversat fizic (capul în jos, mers pe mâini) sau învierea din greșeală a monstrului de lângă tine.
*   **Programarea Loot-ului:** Orice obiect valoros din dungeon poate fi păstrat în loc de vândut și programat ca echipament (ex: un cazan de cupru valoros poate fi codat să devină un scut magnetic sau o capcană automată).

---

## 6. CHAOS ENGINE — ERORILE CA FEATURES COMICE

Atunci când un script conține o eroare de compilare (forțată prin combinarea greșită a runelor sau introducerea de caractere invalide de către Operator) ori dă o excepție la rulare, *Chaos Engine* interceptează problema și activează un efect haotic instantaneu.

### A. Erori de Sintaxă (Syntax Crashes)
Apar când structura blocurilor sau codul text este complet invalid:

*   **Backrooms:** Jucătorul este teleportat instantaneu într-un labirint de birouri cu pereți galbeni râncezi, trebuind să găsească ieșirea fizică înapoi în dungeon.
*   **Chicken Party:** Toată echipa este transformată în găini bouncy care cotcodăcesc haotic pe voice chat, fără acces la vrăji sau unelte timp de 15 secunde.
*   **La Cucaracha Bug:** Un roi masiv de gândaci uriași pixelati invadează încăperea și atacă pe toată lumea.
*   **Inversed Controls:** Direcțiile de mișcare de pe tastatură se inversează pentru toți jucătorii timp de 10 secunde.

### B. Erori de Logică (Runtime Glitches)
Apar în timpul rulării unui cod aparent valid, dar cu logică defectuoasă:

*   **Infinite Loop (Bucla Infinită):** Jucătorul intră în spasme ragdoll necontrolate (corpul se rotește rapid, dărâmând totul în jur ca un titirez) și nu se poate opri până când un prieten nu vine să îi tragă fizic o palmă (Manual Reset prin atac melee).
*   **Division by Zero:** Jucătorul se divide fizic în două jumătăți care fug în direcții diferite, sau se micșorează temporar până la dimensiunea unui atom, făcând ecranul lui să tremure violent.
*   **Buffer Overflow:** Dacă încerci să forțezi valori peste limită (ex: `Sabie.Damage = 9999`), arma explodează violent, aruncândute prin perete, lăsându-te în 5 HP și cu fața plină de funingine ca în desenele animate.

---

## 7. ECONOMIA MAGAZINELOR (THE MEDIEVAL BAY & CORPORATE SHOP)

### A. Magazinul Oficial (Corporate Shop)
Vinde piese autorizate, sigure, dar foarte scumpe. Aici găsești blocuri logice de bază (`IF`, `ELSE`, `WHILE`), senzori, blocuri de mișcare și consumabile strategice:

*   **Debugger-ul:** Un consumabil pe care îl folosești în hub pe codul tău. Îți rulează o simulare sigură și îți confirmă dacă codul tău este stabil sau are bug-uri, eliminând complet riscul de haos în timpul expediției.
*   **AI Genie:** Un asistent duh în lampă în faza de codare. Îi dai prompt text cu ce vrei să programezi și el îți generează codul. Cu cât ești mai puțin specific, cu atât șansa de sabotaj (*Malicious Compliance*) este mai mare (ex: îi ceri să dea foc inamicului, iar el îți dă foc la inventar sau la propriile cizme).

### B. Magazinul de Piraterie: The Medieval Bay
Un magazin ascuns în colțul bazei unde se vând piese "crăpate" (*cracked*) la 80% reducere, dar cu riscuri ascunse de tip troieni magiști, malware și viruși:

*   **Cracked Revive Block:** Are doar 30% șansă de succes. În 70% din cazuri va "fura" viața coechipierului cel mai apropiat pentru a te reanima pe tine.
*   **Spyware Sensor:** Un bloc extrem de ieftin, dar care rulează un keylogger în fundal, furându-ți din aurul colectat la fiecare pas pe care îl faci.
*   **Adware Laser:** Armă extrem de ieftină și puternică, dar care din când în când se blochează și proiectează holograme imense de reclame luminoase și zgomotoase pentru taverne locale, atrăgând instantaneu toți monștrii din zonă.
*   **The Ransomware Spell:** Un bloc care se blochează în dungeon și îți criptează toate vrăjile active. Operatorul sau exploratorul trebuie să plătească fizic aur din inventar hackerilor medievali ca să le debloceze.
*   **WinRAR Spellbook (Licențe Expirate):** O super vrajă care după 30 de utilizări îți blochează ecranul cu o hologramă imensă care îți cere să cumperi licența completă. Trebuie să nimerști un buton microscopic de "Continuă Evaluarea" în timp ce te fugăresc monștrii.

---

## 8. ELEMENTELE DE ATMOSFERĂ, MONȘTRII ȘI GLITCH-URILE FIZICE

*   **The Cookie Monsters:** Dacă accepți "cookies" de pe terminale medievale dubioase, se spawnează mici biscuiți fizici care se prind de corpul tău, făcându-te din ce în ce mai greu și mai încet, până când un coleg te curăță fizic.
*   **The Latency Curse (Lag Magic):** Blestem aruncat de inamici sau bug-uri care aplică rubberbanding fizic (te teleportează înapoi 3 metri din mers) sau îți întârzie acțiunile cu 2 secunde.
*   **The CAPTCHA Gates:** Poți deschide certain uși de securitate doar dacă rezolvi rapid un CAPTCHA pe tabletă sub presiunea timpului (ex: "selectează toate pozele cu căruțe medievale").
*   **The Garbage Collector:** Un schelet uriaș cu o mătură din nuiele care patrulează prin dungeon și "șterge" fizic tot ce e lăsat pe jos: loot, capcane de cod active sau iteme temporare.
*   **Pop-up Phantoms:** Fantome mici sub formă de ferestre de spam care îți blochează ecranul. Operatorul le poate închide de la distanță pe terminal, sau exploratorii le pot lovi fizic cu arma.
*   **The Stack Overflow Ghost:** O masă amorfă de caractere roz neon luminoase și erori care bântuie dungeon-ul. Este creată din toate blocurile stricate și scripturile pe care Operatorul le-a aruncat în Recycle Bin și folosește propriile tale coduri șterse ca să te atace!
*   **The Blue Screen of Death (BSOD) Barrier:** Când un cod dă un crash catastrofal de sistem, în fața jucătorului apare o placă masivă de piatră albastră cu textul de eroare. Jucătorul este blocat și nevăzător până când un coleg vine și îi dă fizic o manetă de "Hard Reboot" pe spate.
*   **The Duck Debugger Monster:** O rață gigantică de cauciuc care patrulează în tăcere. Când te vede, îți citește codul actual cu o voce robotizată și activează instantaneu orice vulnerabilitate ascunsă în scripturile tale (ex: îți forțează cizmele să o ia la goană necontrolat spre un hău).
*   **Hot-Tub Debugging:** În hub, jucătorii stau într-un jacuzzi medieval care scoate bule verzi (*Antivirus Bath*) pentru a se curăța pe ei și echipamentele lor de virușii și spyware-ul adunate din magazinul pirat Medieval Bay.

---

## 9. ARHITECTURA TEHNICĂ (MVP BARE-BONES ÎN GODOT 4.X)

Pentru a asigura o dezvoltare rapidă și stabilă a unui prototip de tip **MVP (Minimum Viable Product)**, se va folosi următoarea structură curată în Godot 4.x.

### A. Structura de Directoare Recomandată
```text
res://
├── .godot/
├── assets/                  # Resurse statice (3D, 2D, Audio, UI)
│   ├── models/              # Modele low-poly (Pilgrim style)
│   ├── textures/            # Texturi pixelate / hand-painted
│   ├── audio/               # Efecte sonore și muzică retro-medievală
│   └── ui/                  # Grafică UI (neon-style, cască VR, tablete)
├── scenes/                  # Scene Godot (.tscn)
│   ├── main_menu.tscn       # Meniul principal
│   ├── hub/                 # Hub-ul / Buncărul medieval
│   │   ├── hub.tscn
│   │   └── hot_tub.tscn
│   ├── dungeon/             # Dungeon-ul procedural (MVP simple generator)
│   │   ├── dungeon.tscn
│   │   └── pieces/          # Piese modulare de grid 10x10 pentru generator
│   │       ├── entrance_piece.tscn
│   │       ├── hallway_piece.tscn
│   │       └── ... (cele 7 piese color-coded)
│   └── player/              # Scenele pentru jucători
│       ├── explorer_player.tscn
│       └── operator_player.tscn
├── scripts/                 # Scripturi GDScript (.gd)
│   ├── autoload/            # Singletons de sistem
│   │   ├── game_manager.gd  # Starea generală a jocului, Quota, scor
│   │   ├── network_manager.gd # Managementul conexiunilor și lobby-urilor
│   │   └── chaos_engine.gd  # Prinderea erorilor și aplicarea de efecte
│   ├── player/              # Logica jucătorilor
│   │   ├── player_movement.gd
│   │   └── interpreter.gd   # Interfețele de codare / rularea scripturilor
│   ├── interactables/       # Obiecte interactive (loot, uși, magazin)
│   └── enemies/             # Logica inamicilor AI basic
└── project.godot
```

### B. Networking & Multiplayer (Godot 4.x High-Level Multiplayer)
Sistemul de multiplayer online stabil va fi construit direct folosind API-ul high-level din Godot 4:
*   **ENetMultiplayerPeer:** Folosit ca peer implicit pentru conexiuni client-server rapide și eficiente.
*   **MultiplayerSpawner:** Nod din Godot 4 plasat în scenă pentru a instanția automat jucătorii și inamicii pe toți clienții atunci când sunt spawnați pe server.
*   **MultiplayerSynchronizer:** Nod adăugat la scenele de jucători și obiecte fizice pentru a replica automat poziția, rotația, viața (HP) și stările esențiale (de exemplu, transformarea în găină), fără a scrie cod de rețea manual.
*   **RPC-uri clare:**
    *   `@rpc("any_peer", "reliable")` pentru interacțiuni discrete și sigure (cumpărături din shop, declanșare revive rurinc, cerere alocare RAM).
    *   `@rpc("authority", "unreliable")` pentru transmiterea datelor de poziționare rapidă sau fizică ragdoll.

### C. Sistemul de Programare (Interpreter MVP)
Pentru faza de Bare-bones, scriptarea nu va folosi un compilator real de limbaj complex, ci un sistem bazat pe **structuri de date (Dictionary/JSON)** interpretate în timp real în `interpreter.gd`:
*   Fiecare echipament sau parte a corpului are o listă de atribute (ex: `speed = 5.0`, `gravity = 9.8`, `is_ragdoll = false`).
*   Blocurile Scratch/Text sunt traduse local într-o listă de instrucțiuni simple (ex: `[{"op": "SET", "var": "speed", "val": 15}, {"op": "WAIT", "val": 5}]`).
*   Interpreterul parcurge această listă. Dacă detectează o excepție (valoare prea mare, buclă infinită fără `WAIT`), emite un semnal către `ChaosEngine` pe server: `ChaosEngine.trigger_runtime_glitch(player_id, glitch_type)`.

### D. Structura de Bază a Chaos Engine
Nodul Singleton `chaos_engine.gd` primește notificări despre erori și apelează RPC-uri pentru a sincroniza efectul haotic pe toți clienții:
```gdscript
# Exemplu conceptual de structură pentru chaos_engine.gd în Godot 4
extends Node

signal error_intercepted(player_id: int, type: String)

func trigger_syntax_crash(player_id: int, crash_type: String) -> void:
	match crash_type:
		"CHICKEN_PARTY":
			rpc("apply_chicken_party", player_id)
		"BACKROOMS":
			rpc("teleport_to_backrooms", player_id)

@rpc("call_local", "reliable")
func apply_chicken_party(player_id: int) -> void:
	# Codul care înlocuiește modelul 3D cu o găină bouncy, activează ragdoll
	# și modifică vocea sau dezactivează controalele de vrăji temporar.
	pass
```

---

## 10. GHIDUL AGENTULUI & PROTOCOALE DE COMPORTAMENT

Această secțiune este de importanță critică pentru orice Agent AI care accesează acest repository. Regulile de mai jos sunt stricte și trebuie respectate cu sfințenie pentru a menține calitatea codului și a preveni regresia sau repetarea greșelilor.

### A. Reguli Fundamentale de Codare în Godot 4.x (GDScript)
1.  **Static Typing Obligatoriu:** Folosește tipizarea statică peste tot unde este posibil pentru a asigura stabilitatea codului și auto-completarea corectă.
	*   *Corect:* `var player_health: int = 100` sau `func calculate_ram(allocated: float) -> void`
	*   *Incorect:* `var player_health = 100` sau `func calculate_ram(allocated)`
2.  **Adnotări Noi:** Folosește sintaxa oficială de Godot 4:
	*   `@onready var ...` (nu `onready var ...`)
	*   `@export var ...` (nu `export var ...`)
	*   `@rpc("any_peer")` (nu cuvântul cheie vechi `remote` sau `master`)
3.  **Separarea UI de Logică:** Niciun script de UI (User Interface) nu trebuie să conțină logică de gameplay directă. Folosește semnale pentru a notifica managerii despre acțiunile utilizatorului și lasă Singletons precum `GameManager` să decidă starea jocului.
4.  **Fizica Haotică:** Pentru mecanicile bouncy și ragdoll, utilizează corect nodurile de fizică din Godot 4 (`CharacterBody3D` pentru mișcare controlată, `RigidBody3D` pentru obiecte aruncate, comori și simulări complet fizice).

### B. Protocolul de Memorare și Feedback (Avoiding Double Mistakes)
Pentru a asigura că Agentul își amintește preferințele utilizatorului și deciziile arhitecturale dintr-o sesiune în alta:
1.  **Actualizare după Feedback:** De fiecare dată când utilizatorul respinge o propunere, indică o eroare de design sau cere o modificare de logică, Agentul **este obligat** să adauge acea regulă sau constrângere în capitolul `C. Lessons Learned / Known Constraints` de mai jos.
2.  **Consultare la Început de Sesiune:** La începerea oricărei sesiuni de lucru sau înainte de a scrie cod, Agentul va citi în întregime secțiunea 10 pentru a se asigura că nu repetă greșelile din trecut.

### C. Lessons Learned / Known Constraints
*(Această listă va fi extinsă pe parcurs de către Agent pe măsură ce primește feedback de la utilizator).*

*   **Regula LL-01 (Scope Limit):** Focusul curent este pe un **Bare-bones game / MVP (Minimum Viable Product)**. Sistemul de Modding nativ și alte funcționalități extrem de avansate sunt amânate și nu reprezintă o prioritate.
*   **Regula LL-02 (Godot Version Constraint):** Toate elementele de design tehnic și eventualele prototipuri de cod trebuie scrise exclusiv pentru **Godot 4.x** și **GDScript modern**.
*   **Regula LL-03 (Language Boundary):** Documentul `agents.md` și comunicarea cu utilizatorul se vor desfășura în **limba română**, păstrând însă termenii tehnici consacrați în limba engleză (ex: *multiplayer, RPC, authority, ragdoll, debugging, loop, syntax, runtime, etc.*) pentru a menține precizia profesională.
*   **Regula LL-04 (Multiplayer Spawner Names):** Atunci când instanțiem scene dinamice în rețea care sunt replicate prin `MultiplayerSpawner`, adăugarea lor în arborele de scene trebuie făcută exclusiv prin `add_child(node, true)`. Argumentul `true` forțează generarea de nume lizibile și valide în rețea (evitând caracterele speciale precum `@` din `@RigidBody3D@105`), lucru esențial pentru ca auto-spawn-ul să funcționeze corect fără erori de rețea.
*   **Regula LL-05 (Mouse Filter & Input Event):** Pentru a preveni ca elementele din HUD sau alte panouri de control 2D să blocheze rotația camerei sau mișcarea mouse-ului, rotația trebuie procesată în funcția `_input(event)` (nu în `_unhandled_input(event)`). De asemenea, toate elementele UI de tip `Control` trebuie configurate cu `mouse_filter = MOUSE_FILTER_IGNORE` (`2`) dacă nu necesită interacțiune directă cu mouse-ul.
*   **Regula LL-06 (Dungeon Grid Alignment):** Toate piesele modulare de dungeon trebuie modelate pe un grid pătrat matematic fix de exact `10x10` metri, cu originea locală la `(0, 0, 0)`. Această scală exterioară este obligatorie pentru a asigura îmbinarea perfectă fără spații/goluri (void) sau suprapuneri, indiferent de cât de înguste sau întortocheate sunt coridoarele din interiorul piesei.

---

## 11. RAPORT SESIUNI DE DEZVOLTARE & ISTORIC REZOLVĂRI BUGS

### SESIUNEA 1: Implementare Lobby MVP, Platformă 3D de Test & Generator de Dungeon Procedural

#### A. Unde suntem acum (Project State)
Proiectul are un flux complet funcțional și robust de rețea (multiplayer bazat pe ENet în Godot 4.x):
1.  **Meniu Principal Modular (`scenes/main_menu.tscn`):**
    *   S-au implementat sub-panouri modulare adăugate direct în arborele de scene (cu proprietatea **Editable Children** activată, permițând navigarea și editarea vizuală directă): `StartPanel` (Create, Join, Settings, Exit), `JoinPanel` (IP/Port), `LobbyPanel` (4 sloturi de prieteni cu stări de Ready, nume lobby editabil), `SettingsPanel` (placeholder).
2.  **Sistemul de Rețea (`scripts/autoload/network_manager.gd`):**
    *   Autoload global ce gestionează crearea de lobby-uri ca Host și conectarea clienților prin IP/Port temporar (compatibil cu viitoarea integrare Steam Matchmaking).
    *   Sincronizarea automată a numelui lobby-ului și a listei complete de clienți conectați.
    *   Ready / Unready state complet sincronizat prin RPC-uri clare.
3.  **Platforma de Testare 3D (`scenes/testing_platform.tscn`):**
    *   Scenă 3D de bază unde jucătorii spawnează ca exploratori FPS (controler WASD + Spacebar, camera look capturat/eliberat perfect la ESC, fără erori de clipping prin dezactivarea vizibilității propriului corp local).
    *   **Platforma Roșie (Expedition Gate):** O zonă de presiune (Area3D) în colț. Când toți jucătorii din lobby (ex. 1/1, 2/2) stau simultan pe ea, pornește automat un timer vizual și încarcă scena de expediție procedurală.
4.  **Cele 7 Piese Modulare de Dungeon (`scenes/dungeon/pieces/`):**
    *   Piese modulare color-coded pe un grid standard de 10x10 metri: `entrance` (albastru), `hallway` (gri închis), `corner` (gri deschis), `t_junction` (violet), `four_way` (indigo), `room` (portocaliu cu stâlpi), `dead_end` (verde).
5.  **Generator de Dungeon Procedural (`scenes/dungeon/dungeon_generator.tscn` & `scripts/dungeon/dungeon_generator.gd`):**
    *   Un algoritm bazat pe DFS/constraint-satisfaction pornește de la Entrance și alege aleator piese potrivind orientarea porturilor și a rotațiilor de 90 grade, cu o limitare strictă de dimensiune (`max_main_pieces: 10`).
    *   Toate porturile rămase deschise către celule goale sunt sigilate automat cu piese Dead End verzi pentru a sigila complet harta 3D (astfel jucătorii nu pot cădea în void).
    *   Poziționarea și rotația pieselor sunt complet replicate pe clienți.

---

#### B. Bugs Întâmpinate & Rezolvări Tehnice

##### 1. Parse Error: Unknown tag 'ext_scene' in file (În .tscn files)
*   **Problema:** Când am creat manual fișierele de scenă Godot text (`.tscn`), am utilizat greșit cuvântul cheie `ext_scene` pentru a importa scripturi și pachete (ex. `[ext_scene type="Script" ...]`). Acest lucru a blocat parserul oficial din Godot Engine 4.7.1, aruncând erori de tip "corrupt scene" sau "unknown tag".
*   **Rezolvarea:** Am parcurs întregul codebase și am înlocuit corect toate aparițiile cu tag-ul standard acceptat de Godot: **`ext_resource`** (ex. `[ext_resource type="Script" ...]`).

##### 2. Parse Error: Expected 4 arguments for constructor (Color constructor în .tscn)
*   **Problema:** Materialele simple pentru piesele modulare au fost definite în format `.tscn` text ca `albedo_color = Color(r, g, b)`. Parserul Godot pentru fișiere de resurse text se așteaptă la exact **4 argumente** pentru constructorul `Color` (Red, Green, Blue, Alpha). Lipsa argumentului alpha a corupt scenele.
*   **Rezolvarea:** Am actualizat toate declarările de culoare din fișierele `.tscn` la formatul complet cu 4 parametri, adăugând valoarea alpha `1` sau `1.0` (ex: `Color(0.2, 0.6, 1, 1)`).

##### 3. Eroarea multiplayer !is_inside_tree() pe global_position
*   **Problema:** Când serverul instanția jucătorii, scriptul încerca să atribuie poziția 3D prin `player_instance.global_position = ...` înainte de a adăuga nodul în arborele de scene. Acest lucru arunca erori majore deoarece un nod trebuie să fie în interiorul Tree-ului pentru a accesa coordonatele sale globale.
*   **Rezolvarea:** Am mutat codul de poziționare după apelul de adăugare în arbore:
    ```gdscript
    players_node.add_child(player_instance)
    player_instance.global_position = spawn_point.global_position
    ```

##### 4. Piese de Dungeon stivuite la (0,0,0) pe Clienți (Replicare MultiplayerSpawner)
*   **Problema:** În Godot 4.x, `MultiplayerSpawner` detectează adăugarea unui nou copil și trimite un pachet de spawn clienților în momentul apelului `add_child()`. Dacă modificările de `position` și `rotation_degrees` sunt făcute după `add_child()`, clienții vor instanția piesa la poziția implicită `(0,0,0)`, fără a aplica offset-ul și rotația calculate de generator pe server.
*   **Rezolvarea:** Am setat proprietățile locale de transformare direct pe instanță **înainte** de a o adăuga în arborele de scene:
    ```gdscript
    piece_instance.position = Vector3(target_cell.x * 10.0, 0.0, target_cell.y * 10.0)
    piece_instance.rotation_degrees.y = -chosen["rotation_steps"] * 90.0
    pieces_node.add_child(piece_instance)
    ```

##### 5. Conflictul tastei ESC (Mouse Capture)
*   **Problema:** Atât scriptul de mișcare a jucătorului (`player_movement.gd`), cât și cel al platformei de test (`testing_platform.gd`) interceptau evenimentul de ESC (`ui_cancel`). Acest lucru făcea ca cele două scripturi să se "bată" pe cursor, rezultând într-un mouse ascuns/capturat continuu chiar și cu meniul deschis.
*   **Rezolvarea:** Am eliminat controlul ESC din scriptul de mișcare, lăsând scriptul scenei (`testing_platform.gd` și `dungeon_generator.gd`) ca singura autoritate responsabilă de eliberarea cursorului și deschiderea meniului.

##### 6. Blorarea vederii (Neon pink capsule) în First Person
*   **Problema:** Camera fiind poziționată la înălțimea ochilor (`1.5m`) în interiorul capsulei de `1.8m` a modelului jucătorului, exploratorul local privea direct prin interiorul corpului său de culoare roz neon și prin vizorul albastru, rezultând într-un ecran obturat și glitch-uit vizual.
*   **Rezolvarea:** Am adăugat o verificare la inițializarea autorității locale a jucătorului. Dacă suntem autoritatea locală, ascundem propriul `MeshInstance3D` al corpului (`mesh_instance.visible = false`). Clienții conectați pe rețea vor continua să ne vadă capsula în mod normal, în timp ce ecranul nostru va fi perfect curat!

---

### SESIUNEA 2: Implementare Sistem Loot, Inventar 4 Sloturi, HUD & Rezolvare Bug-uri Rețea și Rezoluție

#### A. Unde suntem acum (Project State)
Proiectul are acum un sistem de interacțiune, economie și inventar extrem de solid și sincronizat în rețea:
1.  **Sistem de Loot Sincronizat:**
    *   S-au implementat cuburile de loot de 1x1m (`scenes/interactables/loot_item.tscn`) care folosesc fizică (`RigidBody3D`) și se colorează în funcție de raritate (Common - gri, Uncommon - verde, Rare - galben, Epic - mov).
    *   Prețurile sunt generate aleatoriu pe server în funcție de raritate, iar proprietățile (`rarity`, `price`, `item_color`) sunt sincronizate instantaneu prin `MultiplayerSynchronizer` către toți clienții prin intermediul unui setter reactiv în `loot_item.gd`.
2.  **Inventar și HUD de Tip Lethal Company:**
    *   HUD complet integrat pe ecranul exploratorului, conținând un punct fin pe post de crosshair și o bară de inventar cu 4 sloturi.
    *   Tastele `1-4` schimbă slotul activ, actualizând stilul vizual în HUD (cu highlight cyan neon pentru slotul activ).
    *   Ridicarea obiectelor (`E`) folosește un RayCast3D local, trimite un RPC server-authoritative (`request_pickup`) de validare pentru a evita preluările multiple simultane, șterge obiectul din scenă și îl adaugă în primul slot liber al jucătorului.
    *   Aruncarea/drop-ul (`Q`) solicită serverului să instanțieze obiectul și să-i aplice o viteză fizică în direcția privirii camerei.
3.  **Vizualizare în Mână (Hand Visuals):**
    *   Local (First-Person): Jucătorul își vede propriul cub plutind în mână în fața camerei.
    *   Multiplayer (Third-Person): Alți jucători văd un mic cub colorat atașat de modelul (capsula) partenerului lor atunci când acesta ține ceva în mână, datorită sincronizării culorii prin `MultiplayerSynchronizer`.

---

#### B. Bugs Întâmpinate & Rezolvări Tehnice

##### 1. Blocarea rotației camerei FPS din cauza mouse_filter-ului de HUD
*   **Problema:** După adăugarea panourilor de HUD, controlul mouse-ului pentru rotația camerei s-a blocat complet. În Godot 4, elementele UI de tip Control consumă implicit evenimentele de input.
*   **Rezolvarea:** Am setat proprietatea `mouse_filter = MOUSE_FILTER_IGNORE` (2) pe toate elementele din HUD în `.tscn` și am mutat codul de rotație din `_unhandled_input(event)` în `_input(event)` în scriptul `player_movement.gd`. Acest lucru garantează că rotația mouse-ului este interpretată prima, înainte ca elementele UI să o poată intercepta.

##### 2. Eroarea de rețea `Unable to auto-spawn node with reserved name: @RigidBody3D@...`
*   **Problema:** Atunci când un jucător dădea drop la un obiect, serverul instanția un `RigidBody3D` nou și îl adăuga în arbore. Godot îi genera un nume intern precum `@RigidBody3D@105`. Caracterul `@` este rezervat, iar `MultiplayerSpawner` refuza să replice nodul pe clienți, aruncând erori de spawning.
*   **Rezolvarea:** Am apelat `add_child(loot_item, true)` pe server. Al doilea argument (`true`) forțează Godot să genereze exclusiv nume lizibile și sigure în rețea (ex: `LootItem`, `LootItem2`), rezolvând complet desincronizarea.

##### 3. Pixelarea textului și a elementelor 2D la rezoluție mare (1920x1080)
*   **Problema:** Schimbarea rezoluției din editor la 1920x1080 fără definirea explicită a viewport-ului de bază în setări cauza o pixelare și scalare urâtă a textului și a HUD-ului.
*   **Rezolvarea:** Am configurat explicit rezoluția de bază a viewport-ului la 1920x1080 în `project.godot` sub secțiunea `[display]`, asigurând un rendering crisp și de înaltă definiție pentru interfață.

### SESIUNEA 3: Implementare Flux Exterior (Map1), Uși de Dungeon și Game Loop Fundamental

#### A. Unde suntem acum (Project State)
Proiectul are acum un Game Loop complet funcțional în stil *Lethal Company*, oferind o structură clară de început-mijloc-sfârșit:
1. **Lobby (Testing Platform):** Jucătorii pornesc pe platformă, stau pe zona roșie de expediție, iar la îndeplinirea condiției de pregătire, serverul încarcă harta exterioară.
2. **Harta Exterioară (Map1):** O nouă scenă exterioară dedicată (`scenes/map1/map1.tscn` și `scripts/map1/map1.gd`) ce simulează exteriorul dungeon-ului. Conține spawn-uri pentru exploratori, o structură de intrare masivă și generatorul de dungeon procedural situat sub pământ la un offset de siguranță (Y = -100).
3. **Mecanica de Uși de Dungeon (Dungeon Doors):**
   - S-a creat o nouă scenă de interacțiune statică reutilizabilă: `DungeonDoor` (`scenes/interactables/dungeon_door.tscn` și `scripts/interactables/dungeon_door.gd`).
   - Două uși sunt plasate static în scenă la încărcare: una în exterior (`ExteriorDoor`) și una în interiorul punctului de intrare al dungeon-ului (`InteriorDoor`).
   - Ușile folosesc grupul dedicat `door` și sunt complet integrate cu RayCast-ul local al jucătorilor, afișând prompt-uri dinamice iluminate cyan neon: `[E] Enter Dungeon` și `[E] Exit Dungeon`.
4. **Sistem de Teleportare Server-Authoritative:**
   - La apăsarea tastei `E`, clientul trimite un RPC sigur către server (`request_door_interact`).
   - Serverul validează acțiunea și teleporteză instantaneu jucătorul la poziția ușii pereche.
   - Poziția este sincronizată în timp real la toți clienții conectați prin `MultiplayerSynchronizer`.
   - Toate obiectele adunate în inventar (loot-ul) sunt perfect păstrate și transportate între exterior și interior.

#### B. Bugs Întâmpinate & Rezolvări Tehnice

##### 1. Sincronizarea Ușilor Dinamice în Rețea
* **Problema:** Inițial, ușa din interiorul dungeon-ului era generată dinamic de server la pornire și adăugată ca și copil în generator. Fără un `MultiplayerSpawner` configurat special să asculte de noi uși, clienții nu instanțiau ușa local, neputând să o vadă sau să interacționeze cu ea.
* **Rezolvarea:** Am simplificat și optimizat designul, plasând ambele uși (`ExteriorDoor` și `InteriorDoor`) static în scena `map1.tscn` la încărcare. Acest lucru garantează că toți clienții încarcă și instanțiază ușile instantaneu și sincron, serverul ocupându-se doar de corelarea și sincronizarea destinațiilor de teleportare (`target_position`) prin RPC la început.

##### 2. Eșecul de Teleportare al Clienților prin Uși din cauza Autorității Rețelei (MultiplayerAuthority)
* **Problema:** Când un jucător client apăsa tasta `E` pe o ușă, serverul primea cererea de teleportare și încerca să seteze direct coordonatele jucătorului (`p_node.global_position = target_pos`). Însă, deoarece clienții dețin autoritatea rețelei (`MultiplayerAuthority`) asupra propriului lor nod de mișcare FPS, orice modificare de poziție făcută pe server era complet ignorată și suprascrisă în cadrul următor de sincronizarea automată (`MultiplayerSynchronizer`) a clientului, blocând teleportarea.
* **Rezolvarea:** Am implementat o funcție RPC suplimentară de teleportare securizată numită `teleport_to(target_pos: Vector3)` pe clienți. Serverul identifică acum peer-ul care a solicitat teleportarea, iar în loc să-i forțeze poziția direct, trimite un apel `rpc_id` către acel client specific (dacă este client conectat) sau aplică poziția local direct (dacă este Host-ul/Serverul local). Clientul își setează astfel local noua poziție, iar `MultiplayerSynchronizer` o propagă de jos în sus, garantând o teleportare sigură și bidirecțională (intrare/ieșire din dungeon) fără pierderi de pachete.

##### 3. Generare Dublă a Dungeon-ului și Suprapunere de Caractere (Double-Spawning)
* **Problema:** Deoarece `DungeonGenerator` a fost instanțiat ca un copil static în scena `map1.tscn`, funcția sa de `_ready()` rula automat în paralel cu `map1.gd`. Ambele scripturi încercau să genereze dungeon-ul procedural și să spawneze jucătorii în același timp. Acest lucru cauza generarea a două structuri suprapuse ("platforme unele peste altele"), overlap-ul a două interfețe HUD (care producea flicker și bug-uri vizuale pe textul de holding/active item), precum și duplicarea nodurilor de jucători.
* **Rezolvarea:** Am adăugat un filtru în `dungeon_generator.gd`'s `_ready()`. Acesta verifică dacă generatorul rulează ca scenă principală de sine stătătoare (în modul de testare/offline) sau ca parte din `Map1`. Dacă este copil în `Map1`, generatorul își distruge UI-ul CanvasLayer local suprapus și deleagă în întregime inițializarea, generarea unică și spawnarea corectă a jucătorilor către scriptul părinte `map1.gd`.

##### 4. Teleportarea Eronată și Pierderea Obiectelor Aruncate (Loot Drop Bug)
* **Problema:** Când un jucător dădea drop la un obiect (`Q`), serverul instanția loot-ul și îi seta coordonatele folosind `loot_item.position = spawn_pos` înainte de a adăuga nodul în scenă. Deoarece `spawn_pos` este o poziție globală, iar elementele de loot erau adăugate ca copii în containerul de loot al generatorului situat la offset-ul `Y = -100`, coordonatele locale deveneau relative la offset, teleportând instantaneu obiectele aruncate în dungeon (dacă erai afară) sau în vid (dacă erai în dungeon).
* **Rezolvarea:** Am corectat procesul de spawnare a loot-ului în `request_drop`. Acesta rezolvă acum dinamic containerul corect de loot în funcție de scena activă (prin `get_tree().current_scene`), adaugă copilul în arbore, iar apoi îi setează coordonata globală direct prin `loot_item.global_position = spawn_pos`. Acest lucru asigură că obiectele aruncate cad precis pe sol în locul dorit, atât în interiorul cât și în exteriorul dungeon-ului.

---

### SESIUNEA 4: Implementare Core Loop Evacuare, Platformă Verde, Ștergere Inventar & Auto-vânzare în Lobby

#### A. Unde suntem acum (Project State)
Proiectul are acum un Game Loop complet și robust la nivel de MVP (Minimum Viable Product):
1. **Platforma Verde de Colectare & Evacuare (Green Platform):**
   * Creată o scenă 3D de platformă verde reutilizabilă (`scenes/interactables/green_platform.tscn` și `scripts/interactables/green_platform.gd`) integrată în `map1.tscn` și `testing_platform.tscn`.
2. **Mecanica de Countdown Sincronizată pe Server (Confirmation & Escape):**
   * Când toți jucătorii activi sunt prezenți pe platforma verde exterioară, pornește un timer de confirmare de 10 secunde (se anulează instantaneu dacă un jucător părăsește platforma).
   * La finalul confirmării, se activează numărătoarea inversă de evacuare de 15 secunde.
   * Jucătorii lăsați în urmă sunt eliminați fizic și își pierd tot inventarul.
3. **Wipe total de inventar la evacuare (Core Loop Carryover Fix):**
   * Orice item ținut în inventar sau în mână este complet șters la evacuare prin RPC-uri clare de curățare a inventarului (`clear_inventory`), respectând regula de a nu putea căra obiecte în mână la teleportarea în lobby.
4. **Teleportare physical-loot și Spawning în Lobby:**
   * Doar itemele (loot-ul) aflate fizic pe platforma verde exterioară la scurngerea timpului sunt salvate în `NetworkManager` și teleportate/spawnate în lobby pe platforma verde interioară.
5. **Auto-vânzare în Lobby cu delay de 5 secunde:**
   * Loot-ul spawnat sau adus manual pe platforma din Lobby are un delay de 5.0 secunde (oferind feedback vizual direct jucătorilor) înainte de a fi vândut automat, adăugând credite în soldul global (`team_credits`).
6. **HUD HUD credite și countdown:**
   * Adăugate elementele dinamice `CreditsLabel` (stânga sus) și `EscapeLabel` (centru sus, sincronizată prin RPC) pe interfața jucătorului.

#### B. Bugs Întâmpinate & Rezolvări Tehnice

##### 1. Eșec de detecție loot pe platformă (Collision Mask)
* **Problema:** Platforma verde avea `collision_mask = 3`, dar loot items au `collision_layer = 4` (bit 3). Am crescut masca la `collision_mask = 7` (detectează și layer 2 de jucători, și layer 4 de loot).
* **Rezolvarea:** Am actualizat `collision_mask = 7` pe Area3D a platformei verzi în `.tscn` pentru a intercepta și înregistra corect obiectele de loot.

##### 2. Duplicare / Reapariție iteme din inventar (Stale Inventory State)
* **Problema:** Itemele din mâini reapăreau când jucătorii se întorceau în expediție deoarece inventarele erau memorate persistente. Am scos salvarea inventarului pentru a forța carryover strict bazat pe platformă (no inventory keep on escape).
* **Rezolvarea:** Am implementat RPC-ul `clear_inventory` pe player_movement, apelat pe server la evacuare pentru a asigura un wipe complet al inventarului pe toți clienții.

##### 3. Vânzare fantomă (Race condition)
* **Problema:** Dacă un jucător ridica o piesă de pe platforma din lobby în cele 5 secunde, piesa se vindea în continuare și dispărea din mână.
* **Rezolvarea:** Am adăugat o verificare `if not loot_node in loot_on_platform: return` în funcția de vânzare pentru a opri vânzarea automată dacă piesa este ridicată în timpul delay-ului de 5 secunde.

---

## 12. SISTEMUL DE DATE & ECONOMIE: DIGITIZARE, GIT PULL ȘI HARD DISK DROP

Această secțiune definește mecanica centrală și unică de transport și valorificare a resurselor (Loot-ului) din dungeon pentru atingerea cotei corporatiste (**Quota**). Sistemul elimină transportul fizic tradițional de cutii și îl înlocuiește cu un flux asimetric bazat pe **Digitizare, Transfer de Date (Git Pull), Hacking și Securitate Cibernetică**.

### A. Fluxul Principal de Gameplay (The Data Pipeline)

1.  **Digitizarea locală (Exploratorii):**
    *   Când un explorator găsește un cub de loot în dungeon, el nu îl pune într-un rucsac fizic, ci îl scanează cu tableta.
    *   La scanare, obiectul fizic este de-alocat din simulare (dispare din 3D Space), iar proprietățile lui (`rarity`, `price`, `item_color`) sunt stocate virtual în tableta exploratorului sub formă de fișier de date (ex: `loot_834.dat`).
    *   **Limita de Stocare (Local Buffer):** Tableta are un spațiu limitat de buffer (ex: **50MB**). Fiecare tip de raritate ocupă o dimensiune diferită:
        *   *Common:* 5MB (Valoare mică, dar ocupă spațiu).
        *   *Uncommon:* 10MB.
        *   *Rare:* 20MB.
        *   *Epic:* 35MB (Valoare uriașă, ocupă mult spațiu).
    *   Dacă stocarea este plină (`100% Buffer Overflow`), exploratorul nu mai poate scana alte obiecte. El va trebui fie să le poarte fizic în mână (ocupând slot-ul activ, făcându-l incapabil să folosească alte unelte), fie să aștepte ca Operatorul să descarce datele.

2.  **Descărcarea de Date (Git Pull de la Operator):**
    *   La terminalul de monitorizare din buncăr, Operatorul vede starea stocării exploratorilor în timp real: `Explorer_1 Storage: 45MB/50MB [Ready to Pull]`.
    *   Operatorul trebuie să ruleze comanda text `git pull explorer_1` sau să apese un buton pe interfață pentru a începe descărcarea.
    *   **Viteza și Interferențele (Latency & Blockers):**
        *   Descărcarea durează câteva secunde.
        *   Viteza de transfer scade dacă exploratorul este foarte departe în dungeon, dacă se află în camere adânci cu interferențe runice, sau dacă un inamic bruiază semnalul.
        *   Dacă descărcarea este completă (100%), buffer-ul local al exploratorului se resetează la `0MB`, iar banii sunt transferați instantaneu în soldul buncărului pentru îndeplinirea cotației (**Quota**).

3.  **Moartea Jucătorului și Recuperarea Hard Disk-ului (The Hard Disk Drop):**
    *   Dacă un explorator moare în dungeon înainte ca datele din buffer-ul lui să fie descărcate de Operator, tot loot-ul nescărcat este salvat local într-un **Hard Disk fizic masiv și strălucitor (HDD-ul de Urgență)** care cade pe jos lângă corpul său.
    *   Coechipierii rămași în viață trebuie să meargă la locul decesului, să ridice fizic HDD-ul în mână și să-l transporte în buncăr pentru a downloada manual datele. Dacă HDD-ul este abandonat sau pierdut, toate acele obiecte scanate sunt șterse definitiv din memorie.

4.  **Jocul fără Operator (No-Operator Mode):**
    *   Dacă echipa decide să joace fără Operator (sau joacă solo), ei pot stoca în continuare iteme scanate pe tabletă până la limita de 50MB.
    *   Pentru a le descărca, ei trebuie să se întoarcă fizic în buncăr la sfârșitul expediției, să acceseze terminalul central și să ruleze manual procesul de descărcare (Git Pull), rămânând vulnerabili la ambuscade în timp ce procesul rulează lent.

### B. Mecanici Secundare & Riscuri (Cyber-Medieval Hazards)

1.  **Coruperea Datelor (Data Corruption & Glitches):**
    *   Dacă un explorator este lovit de un monstru sau stă prea mult în zone instabile din dungeon, fișierele de date din tabletă pot începe să se corupă.
    *   Valoarea în bani a itemelor scade cu 1% pe secundă. Operatorul poate rula un protocol de deparazitare sau curățare de pe terminal (`git clean` sau `antivirus_scan`) pentru a opri degradarea.
2.  **Blocul de Scriptare Unic (The Auto-Transfer Block):**
    *   Un bloc Scratch special ce poate fi cumpărat din magazin, numit `PushBlock()` sau `TransmitSpell()`. Jucătorii își pot programa tableta sau armele să uploadeze automat buffer-ul de date în buncăr în anumite condiții (ex: `if (speed == 0) -> PushBlock()`), cu un consum suplimentar de Mana-Credits.

---

## 13. ROADMAP OFICIAL DE DEZVOLTARE (DIRECȚIA MVP SPRE STEAM ALPHA)

Pentru a asigura o dezvoltare fluidă, eficientă și extrem de motivantă (fără a ne bloca în detalii prea devreme), am stabilit de comun acord următorul Roadmap în etape clare. Prioritatea este de a avea un joc funcțional de tip **Lethal Company/Pilgrim** la nivel de bază, transformându-l iterativ într-un produs unic de succes pentru Steam Wishlists.

### ETAPA 1: LUMINĂ ȘI ATMOSFERĂ (Următorul pas)
*   **Scop:** Schimbarea atmosferei jocului de la un prototip steril de "Tetris" la un veritabil survival horror medieval-cyberpunk.
*   **Livrabile:**
    *   Sistem de iluminare dramatic în Dungeon (întuneric profund, lumini Omni de tip torțe de perete slabe, ceață volumetrică low-poly).
    *   Sistem de lanterne sau torțe pe ulei pentru exploratori (consumabile sau programabile).
    *   Shader retro de pixelare / dithered (vibe PSX/Pilgrim de rezoluție redusă) aplicat pe camera jucătorilor pentru a oferi un stil artistic instantaneu captivant.

### ETAPA 2: INTEGRĂRI ASSET-URI EXTERNE (Să arate profi pentru Steam)
*   **Scop:** Înlocuirea completă a capsulelor de jucători și a blocurilor de testare 3D cu modele low-poly atractive, fără a pierde timp cu modelarea manuală de la zero.
*   **Livrabile:**
    *   Descărcarea și integrarea de modele 3D gratuite/publice (CC0/low-poly) de pe internet pentru inamici, jucători și obiecte de loot (ex. cupe de aur, săbii ruginite, tablete, baze metalice).
    *   Decorarea pieselor de dungeon 10x10 cu texturi retro ruginite, stâlpi de piatră și detalii de buncăr medieval.

### ETAPA 3: PROGRAMARE ȘI HOTFIX-URI (Sistem de bază Lethal Company)
*   **Scop:** Stabilizarea codului existent și adăugarea primilor inamici/pericole pentru a face jocul cu adevărat distractiv în sesiunile de playtest.
*   **Livrabile:**
    *   Remedierea eventualelor bug-uri, optimizări de sincronizare multiplayer și fluidizarea controalelor actuale.
    *   Implementarea primului monstru de bază care patrulează prin Dungeon și fugărește exploratorii (pentru MVP, acesta va fi reprezentat simplu printr-un Sprite 2D tip "clasicul PNG Godot" în spațiu 3D care se mișcă spre jucători și le dă damage).
    *   Sistem de spawnare de inamici pe server sincronizat pe clienți.

### ETAPA 4: POLISH — FAZA 1 (Finisare elemente de bază)
*   **Scop:** Oferirea unui feedback senzorial satisfăcător pentru acțiunile de bază ale jucătorilor.
*   **Livrabile:**
    *   Sunete retro (pași în ecou pe piatră, sunet de pickup/drop loot, alarme de countdown).
    *   Îmbunătățirea interfeței (HUD) cu efecte de tip glitch neon și indicatori mai clari pentru starea coechipierilor și a inventarului.
    *   Sesiuni de playtest co-op pe rețea locală / online pentru identificarea problemelor de gameplay.

### ETAPA 5: PROGRAMARE LUCRURI UNICE (Identity & Innovation)
*   **Scop:** Introducerea mecanicilor unice descrise în GDD care fac acest joc diferit de orice alt clona de Lethal Company.
*   **Livrabile:**
    *   **Digitizarea Loot-ului:** Scanarea obiectelor în tablete, gestionarea spațiului de Buffer (MB) și limitarea capacității locale de stocare.
    *   **Terminalul Operatorului & Git Pull:** Adăugarea terminalului interactiv din buncăr unde Operatorul scrie comenzi reale (`git pull`, `git clean`) pentru a descărca datele exploratorilor și a le transforma în bani.
    *   **Hard Disk Drop (HDD):** Drop-ul fizic al unui HDD masiv la locul morții jucătorului pentru a recupera manual datele nescărcate.
    *   **Chaos Engine:** Trigger-ul de glitch-uri comice (Chicken Party, Backrooms, inversare taste, etc.) atunci când codul sau conexiunile se corup.

### ETAPA 6: POLISH FINAL SPRE STEAM WISHLISTS
*   **Scop:** Împachetarea jocului într-un build perfect stabil și optimizat pentru publicare și promovare.
*   **Livrabile:**
    *   Sistem de Quota progresiv (Zile/Cote de îndeplinit) și scenariul de eșec (Soul Defrag / Recycle Bin reset).
    *   Polishing pe partea de rețea, eliminarea oricăror erori din logs.
    *   Crearea materialelor vizuale (capturi de ecran atrăgătoare, gameplay capturat în 4 jucători) pentru lansarea paginii de Steam și începerea campaniei de Wishlist.
