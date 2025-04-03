using Renci.OS.SshNet;
using System;
using System.Windows.Forms;
using System.DirectoryServices.AccountManagement; // AD-Abfragen
using System.Diagnostics; // Debug-Ausgaben
using System.Collections.Generic;

namespace OtoboAD
{
    public partial class Form1 : Form
    {
        public Form1()
        {
            InitializeComponent();
            txtHost.Text = "192.168.116.26";  // IP der VM
            txtUser.Text = "root";            // SSH-Benutzername
            txtPassword.Text = "";            // Passwort muss eingegeben werden

            LoadADMembers();
        }

        private void LoadADMembers()
        {
            try
            {
                using (PrincipalContext ctx = new PrincipalContext(ContextType.Domain, "goevb.de", "OU=OTOBO,DC=goevb,DC=de"))
                {
                    GroupPrincipal group = GroupPrincipal.FindByIdentity(ctx, "OTOBOAgentUser");
                    if (group != null)
                    {
                        foreach (Principal p in group.GetMembers())
                        {
                            checkedListBoxADMembers.Items.Add(p.SamAccountName, false);
                        }
                    }
                    else
                    {
                        MessageBox.Show("Die Gruppe 'OTOBOAgentUser' wurde nicht gefunden.");
                    }
                }
            }
            catch (Exception ex)
            {
                MessageBox.Show("Fehler beim Laden der AD-Mitglieder: " + ex.Message);
            }
        }

        private void checkedListBoxADMembers_SelectedIndexChanged(object sender, EventArgs e)
        {
            if (checkedListBoxADMembers.SelectedItem != null)
            {
                string selectedUser = checkedListBoxADMembers.SelectedItem.ToString();

                try
                {
                    using (PrincipalContext ctx = new PrincipalContext(ContextType.Domain, "goevb.de"))
                    {
                        UserPrincipal user = UserPrincipal.FindByIdentity(ctx, selectedUser);
                        if (user != null)
                        {
                            lblDetailFirstName.Text = "Vorname: " + (user.GivenName ?? "Unbekannt");
                            lblDetailLastName.Text = "Nachname: " + (user.Surname ?? "Unbekannt");
                            lblDetailEmail.Text = "Email: " + (user.EmailAddress ?? "Keine E-Mail");
                        }
                    }
                }
                catch (Exception ex)
                {
                    MessageBox.Show("Fehler beim Abrufen der Benutzerdetails: " + ex.Message);
                }
            }
        }

        private void btnExecute_Click(object sender, EventArgs e)
        {
            string host = txtHost.Text;
            string sshUser = txtUser.Text;
            string sshPassword = txtPassword.Text;

            List<string> selectedUsers = new List<string>();

            foreach (var item in checkedListBoxADMembers.CheckedItems)
            {
                selectedUsers.Add(item.ToString());
            }

            if (selectedUsers.Count == 0)
            {
                MessageBox.Show("Bitte wählen Sie mindestens einen Benutzer aus.");
                return;
            }

            try
            {
                using (var client = new SshClient(host, sshUser, sshPassword))
                {
                    client.HostKeyReceived += (s, eArgs) => { eArgs.CanTrust = true; };
                    client.KeepAliveInterval = TimeSpan.FromSeconds(30);
                    client.Connect();

                    if (client.IsConnected)
                    {
                        foreach (string user in selectedUsers)
                        {
                            using (PrincipalContext ctx = new PrincipalContext(ContextType.Domain, "goevb.de"))
                            {
                                UserPrincipal adUser = UserPrincipal.FindByIdentity(ctx, user);
                                if (adUser != null)
                                {
                                    string firstName = adUser.GivenName ?? "Unbekannt";
                                    string lastName = adUser.Surname ?? "Unbekannt";
                                    string email = adUser.EmailAddress ?? $"{user}@goevb.de";

                                    string command = $"docker exec -i otobo-daemon-1 perl /opt/otobo/bin/otobo.Console.pl Admin::User::Add " +
                                                     $"--user-name {user} --first-name \"{firstName}\" --last-name \"{lastName}\" --email-address \"{email}\"";

                                    var cmd = client.RunCommand(command);
                                    Debug.WriteLine($"Befehl: {command}");
                                    Debug.WriteLine($"Ergebnis: {cmd.Result}");
                                    Debug.WriteLine($"Fehler: {cmd.Error}");

                                    if (!string.IsNullOrEmpty(cmd.Error))
                                    {
                                        MessageBox.Show($"Fehler beim Anlegen von {user}: {cmd.Error}");
                                    }
                                    else
                                    {
                                        MessageBox.Show($"Benutzer {user} erfolgreich angelegt.");
                                    }
                                }
                            }
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
