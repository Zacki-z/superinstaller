#!/bin/bash

timeout=10

echo -n "Vill skicka till Proton? (y/n) [auto Y om $timeout sek]: "
read -t "$timeout" svar

# Om inget svar ges – anta Y
svar=${svar:-Y}

if [ "$svar" = "y" ] || [ "$svar" = "Y" ]; then
    echo "✔ Fortsätter..."
else
    echo "✖ Avbryter."
    exit 1
fi
echo "########################################"
