package main

import (
	"fmt"
	"io/ioutil"
	"log"
	"strings"

	"gopkg.in/yaml.v2"
)

// Config struct to hold the YAML data
type Config struct {
	Workers struct {
		Nodes []string `yaml:"nodes"`
	} `yaml:"workers"`
	ControlPlane struct {
		Nodes []string `yaml:"nodes"`
	} `yaml:"controlplane"`
	Command string `yaml:"command"`
}

func main() {
	// Charger le fichier YAML
	yamlFile, err := ioutil.ReadFile("nodes.yaml")
	if err != nil {
		log.Fatalf("Erreur de lecture du fichier YAML: %v", err)
	}

	// Parser le fichier YAML
	var config Config
	err = yaml.Unmarshal(yamlFile, &config)
	if err != nil {
		log.Fatalf("Erreur de parsing du fichier YAML: %v", err)
	}

	// Exécuter la commande pour chaque IP et type
	for _, ip := range config.Workers.Nodes {
		command := strings.ReplaceAll(config.Command, "<ip>", ip)
		command = strings.ReplaceAll(command, "<type>", "worker")
		executeCommand(command)
	}

	for _, ip := range config.ControlPlane.Nodes {
		command := strings.ReplaceAll(config.Command, "<ip>", ip)
		command = strings.ReplaceAll(command, "<type>", "controlplane")
		executeCommand(command)
	}
}

func executeCommand(command string) {
	fmt.Printf("%s\n", command)
	// Ici, vous pouvez ajouter la logique pour exécuter la commande dans votre programme Go.
	// Vous pouvez utiliser la bibliothèque os/exec pour cela.
	// Par exemple:
	// cmd := exec.Command("bash", "-c", command)
	// err := cmd.Run()
	// if err != nil {
	// 	log.Fatalf("Erreur lors de l'exécution de la commande: %v", err)
	// }
}

