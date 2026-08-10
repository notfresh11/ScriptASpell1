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
*   **Buffer Overflow:** Dacă încerci să forțezi valori peste limită (ex: `Sabie.Damage = 9999`), arma explodează violent, aruncându-te prin perete, lăsându-te în 5 HP și cu fața plină de funingine ca în desenele animate.

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
*   **The CAPTCHA Gates:** Poți deschide anumite uși de securitate doar dacă rezolvi rapid un CAPTCHA pe tabletă sub presiunea timpului (ex: "selectează toate pozele cu căruțe medievale").
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
│   │   └── pit_room_base.tscn
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
