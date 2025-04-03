namespace OtoboAD
{
    partial class Form1
    {
        /// <summary>
        /// Erforderliche Designervariable.
        /// </summary>
        private System.ComponentModel.IContainer components = null;

        /// <summary>
        /// Verwendete Ressourcen bereinigen.
        /// </summary>
        /// <param name="disposing">True, wenn verwaltete Ressourcen gelöscht werden sollen, andernfalls False.</param>
        protected override void Dispose(bool disposing)
        {
            if (disposing && (components != null))
            {
                components.Dispose();
            }
            base.Dispose(disposing);
        }

        #region Vom Windows Form-Designer generierter Code

        /// <summary>
        /// Erforderliche Methode für die Designerunterstützung.
        /// </summary>
        private void InitializeComponent()
        {
            this.checkedListBoxADMembers = new System.Windows.Forms.CheckedListBox();
            this.btnExecute = new System.Windows.Forms.Button();
            this.lblHost = new System.Windows.Forms.Label();
            this.txtHost = new System.Windows.Forms.TextBox();
            this.lblUser = new System.Windows.Forms.Label();
            this.txtUser = new System.Windows.Forms.TextBox();
            this.lblPassword = new System.Windows.Forms.Label();
            this.txtPassword = new System.Windows.Forms.TextBox();
            this.lblDetailFirstName = new System.Windows.Forms.Label();
            this.lblDetailLastName = new System.Windows.Forms.Label();
            this.lblDetailEmail = new System.Windows.Forms.Label();

            this.SuspendLayout();

            // 
            // checkedListBoxADMembers
            // 
            this.checkedListBoxADMembers.FormattingEnabled = true;
            this.checkedListBoxADMembers.Location = new System.Drawing.Point(12, 12);
            this.checkedListBoxADMembers.Size = new System.Drawing.Size(250, 200);
            this.checkedListBoxADMembers.TabIndex = 0;
            this.checkedListBoxADMembers.SelectedIndexChanged += new System.EventHandler(this.checkedListBoxADMembers_SelectedIndexChanged);

            // 
            // btnExecute
            // 
            this.btnExecute.Location = new System.Drawing.Point(12, 220);
            this.btnExecute.Size = new System.Drawing.Size(250, 30);
            this.btnExecute.Text = "Benutzer anlegen";
            this.btnExecute.UseVisualStyleBackColor = true;
            this.btnExecute.Click += new System.EventHandler(this.btnExecute_Click);

            // 
            // lblHost
            // 
            this.lblHost.AutoSize = true;
            this.lblHost.Location = new System.Drawing.Point(280, 20);
            this.lblHost.Text = "Host:";

            // 
            // txtHost
            // 
            this.txtHost.Location = new System.Drawing.Point(350, 17);
            this.txtHost.Size = new System.Drawing.Size(200, 23);

            // 
            // lblUser
            // 
            this.lblUser.AutoSize = true;
            this.lblUser.Location = new System.Drawing.Point(280, 50);
            this.lblUser.Text = "Benutzer:";

            // 
            // txtUser
            // 
            this.txtUser.Location = new System.Drawing.Point(350, 47);
            this.txtUser.Size = new System.Drawing.Size(200, 23);

            // 
            // lblPassword
            // 
            this.lblPassword.AutoSize = true;
            this.lblPassword.Location = new System.Drawing.Point(280, 80);
            this.lblPassword.Text = "Passwort:";

            // 
            // txtPassword
            // 
            this.txtPassword.Location = new System.Drawing.Point(350, 77);
            this.txtPassword.Size = new System.Drawing.Size(200, 23);
            this.txtPassword.UseSystemPasswordChar = true;

            // 
            // lblDetailFirstName
            // 
            this.lblDetailFirstName.AutoSize = true;
            this.lblDetailFirstName.Location = new System.Drawing.Point(280, 130);
            this.lblDetailFirstName.Size = new System.Drawing.Size(150, 20);
            this.lblDetailFirstName.Text = "Vorname: -";

            // 
            // lblDetailLastName
            // 
            this.lblDetailLastName.AutoSize = true;
            this.lblDetailLastName.Location = new System.Drawing.Point(280, 160);
            this.lblDetailLastName.Size = new System.Drawing.Size(150, 20);
            this.lblDetailLastName.Text = "Nachname: -";

            // 
            // lblDetailEmail
            // 
            this.lblDetailEmail.AutoSize = true;
            this.lblDetailEmail.Location = new System.Drawing.Point(280, 190);
            this.lblDetailEmail.Size = new System.Drawing.Size(150, 20);
            this.lblDetailEmail.Text = "Email: -";

            // 
            // Form1
            // 
            this.AutoScaleDimensions = new System.Drawing.SizeF(8F, 16F);
            this.AutoScaleMode = System.Windows.Forms.AutoScaleMode.Font;
            this.ClientSize = new System.Drawing.Size(600, 270);
            this.Controls.Add(this.checkedListBoxADMembers);
            this.Controls.Add(this.btnExecute);
            this.Controls.Add(this.lblHost);
            this.Controls.Add(this.txtHost);
            this.Controls.Add(this.lblUser);
            this.Controls.Add(this.txtUser);
            this.Controls.Add(this.lblPassword);
            this.Controls.Add(this.txtPassword);
            this.Controls.Add(this.lblDetailFirstName);
            this.Controls.Add(this.lblDetailLastName);
            this.Controls.Add(this.lblDetailEmail);
            this.Text = "Otobo AD Benutzerverwaltung";
            this.ResumeLayout(false);
            this.PerformLayout();
        }

        #endregion

        private System.Windows.Forms.CheckedListBox checkedListBoxADMembers;
        private System.Windows.Forms.Button btnExecute;
        private System.Windows.Forms.Label lblHost;
        private System.Windows.Forms.TextBox txtHost;
        private System.Windows.Forms.Label lblUser;
        private System.Windows.Forms.TextBox txtUser;
        private System.Windows.Forms.Label lblPassword;
        private System.Windows.Forms.TextBox txtPassword;
        private System.Windows.Forms.Label lblDetailFirstName;
        private System.Windows.Forms.Label lblDetailLastName;
        private System.Windows.Forms.Label lblDetailEmail;
    }
}
