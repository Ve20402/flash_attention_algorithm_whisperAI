Virtuelna platforma
--------------------

# Kako pokrenuti sistem?

Podrazumevamo da je rad na sistemu koji krece Ubuntu 24.04 LTS instalaciju.

## Instaliranje neophodnih paketa za Ubuntu 24.04 LTS

``` sh
<<<<<<< HEAD
apt install git build-essential python3 python3-pip python3-venv libsystemc-dev libportaudio2 make
=======
apt install git build-essential python3 python3-pip python3-dev python3-venv libsystemc-dev libportaudio2 make
>>>>>>> cffb9f15e82dd2e888d7829c84c18740b67a5b56
```

## Namjestanje Python okruzenja

Python programski jezik zahtjeva da se otvori razvojno okruzenje kako bi se mogli
instalirati paketi koji nisu dio operativnog sistema. Da bi smo mu to omogucili,
neophodno je napraviti tkz. "Virtuelno okruzenje" odnosno "Virtual environment"
u koji ce da smesti sve fajlove svih programa i biblioteka koji nam budu trebali
za ovaj projekat.

Ukoliko pokrecemo virtuelnu platformu po prvi put na odredjenom sistemu, neophodno
ga je stvorimo. Uzimajuci u obzir da se nas shell i dalje nalazi unutar projektnog
foldera, pokrecemo sledecu komandu:

```sh
python3 -m venv .venv
```

Nakon toga, za svaki naredni put, da bi smo omogucili to okruzenje trebamo da ga
"aktiviramo" tako sto pokrenemo komandu u zavisnosti od Shell-a kojeg koristimo:

1. Bash/ZSH i ostali POSIX shellovi (najcesci i defaultni slucaj): 

```sh
source .venv/bin/activate
```

2. Fish

```sh
source .venv/bin/activate.fish
```

3. CSH
```sh
source .venv/bin/activate.csh
```

Ukoliko smo upesni, pojavice nam se indikator ``(.venv)`` sa leve strane trenutne
komande koje unosimo na odredjeni shell program.

## Instaliranje Python biblioteka

Nakon sto smo usli u nase Python virtuelno okruzenje, mozemo da instaliramo sve
neophodne pakete tako sto pokrenemo komandu:

```
make install_deps
```

## Pokretanje virtuelne platforme

```
make run_app
```
