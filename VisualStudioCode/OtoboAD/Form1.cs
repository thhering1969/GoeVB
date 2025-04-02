using Renci.OS.SshNet;  // Verwende den korrekten Namespace für OS-SSH.NET
using System;
using System.Windows.Forms;
using System.Diagnostics; // Für Debug-Ausgaben

namespace OtoboAD
{
    public partial class Form1 : Form
    {
        public Form1()
        {
            InitializeComponent();
            // Setze Standardwerte für SSH-Verbindung und Otobo-Benutzerdaten
            txtHost.Text = "192.168.116.26";  // IP der VM
            txtUser.Text = "root";            // SSH-Benutzername (für die VM)
            txtPassword.Text = "";            // Passwort: vom Benutzer eingeben lassen
            txtFirstName.Text = "John";       // Standard-Vorname
            txtLastName.Text = "Doe";         // Standard-Nachname
            txtEmail.Text = "johndoe@goevb.de"; // Standard E-Mail-Adresse
        }

        private void btnExecute_Click(object sender, EventArgs e)
        {
            // Werte aus den Textfeldern holen
            string host = txtHost.Text;
            string sshUser = txtUser.Text;
            string sshPassword = txtPassword.Text;
            string firstName = txtFirstName.Text;
            string lastName = txtLastName.Text;
            string email = txtEmail.Text;

            // Erzeuge den Benutzernamen für Otobo aus Vor- und Nachname (als Beispiel)
            string otoboUser = (firstName + lastName).ToLower();

            // Erstelle den Befehl, der im Docker-Container ausgeführt wird.
            // Hier wird das Otobo-Console-Skript per Perl ausgeführt, um einen Agenten anzulegen.
            string command = $"docker exec -i otobo-daemon-1 perl /opt/otobo/bin/otobo.Console.pl Admin::User::Add --user-name {otoboUser} --first-name {firstName} --last-name {lastName} --email-address {email}";

            try
            {
                // SSH-Verbindung zur VM aufbauen
                using (var client = new SshClient(host, sshUser, sshPassword))
                {
                    client.HostKeyReceived += (s, eArgs) =>
                    {
                        // Alle Host-Schlüssel ohne Überprüfung akzeptieren (nur Testumgebung!)
                        eArgs.CanTrust = true;
                    };

                    client.KeepAliveInterval = TimeSpan.FromSeconds(30);
                    client.Connect();

                    if (client.IsConnected)
                    {
                        // Führe den Docker-Befehl im Container aus
                        var cmd = client.RunCommand(command);
                        string result = cmd.Result;
                        string error = cmd.Error;

                        // Debug-Ausgabe in der Debug-Konsole
                        Debug.WriteLine($"Command executed: {command}");
                        Debug.WriteLine($"Result: {result}");
                        Debug.WriteLine($"Error: {error}");

                        // Zeige entweder die Fehlermeldung oder das Ergebnis an
                        if (!string.IsNullOrEmpty(error))
                        {
                            MessageBox.Show("Fehler: " + error);
                        }
                        else if (!string.IsNullOrEmpty(result))
                        {
                            MessageBox.Show("Ergebnis: " + result);
                        }
                        else
                        {
                            MessageBox.Show("Keine Ausgabe und kein Fehler vom Server.");
                        }
                    }
                    else
                    {
                        MessageBox.Show("Verbindung konnte nicht hergestellt werden.");
                    }

                    client.Disconnect();
                }
            }
            catch (Exception ex)
            {
                MessageBox.Show("Fehler: " + ex.Message);
            }
        }
    }
}
