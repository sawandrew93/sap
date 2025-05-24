add_vglocal_repo:
  cmd.run:
    - name: zypper addrepo -G http://121.54.164.70/15-SP3/ vglocal
    - unless: zypper lr | grep -q vglocal
    - stdout: True

hana_required_packages:
  pkg.installed:
    - pkgs:
      - jq
      - libatomic1
      - rpm-build
      - xmlstarlet
      - python2-pyOpenSSL
      - bc
      - glibc-i18ndata
      - libcap-progs
      - libicu60_2
      - insserv-compat
      - nfs-kernel-server
    - require:
      - cmd: add_vglocal_repo

replace_components_dir_and_give_exec_permission:
  cmd.run:
    - name: |
        hdb_param_file=$(find / -type f -name "hdb_param.cfg" 2>/dev/null | head -n 1)
        cp "$hdb_param_file" /tmp/hdb.cfg
        hana_afl_dir=$(find / -type d -name "SAP_HANA_AFL" 2>/dev/null | head -n 1)
        hana_client_dir=$(find / -type d -name "SAP_HANA_CLIENT" 2>/dev/null | head -n 1)
        hana_db_dir=$(find / -type d -name "SAP_HANA_DATABASE" 2>/dev/null | head -n 1)
        sed -i "s|hana_afl_dir|${hana_afl_dir}|g" /tmp/hdb.cfg
        sed -i "s|hana_client_dir|${hana_client_dir}|g" /tmp/hdb.cfg
        sed -i "s|hana_db_dir|${hana_db_dir}|g" /tmp/hdb.cfg
        if [[ -d "$hana_afl_dir" && -d "$hana_db_dir" && -d "$hana_client_dir" ]]; then
          chmod +x -R "${hana_afl_dir}"
          chmod +x -R "${hana_client_dir}"
          chmod +x -R "${hana_db_dir}"
        else
          echo "Installer for hana database or hana afl or hana client component cannot be found"
          exit 1
        fi
    - shell: /bin/bash
    - stdout: True
    - user: root

hana_install:
  cmd.run:
    - name: |
        hana_db_dir=$(find / -type d -name "SAP_HANA_DATABASE" 2>/dev/null | head -n 1)
        if [[ -d "$hana_db_dir" ]]; then
          cd "$hana_db_dir"
          echo "Installing hana datbase services..."
          ./hdblcm --batch --configfile="/tmp/hdb.cfg"
        fi
    - cwd: /
    - user: root
    - shell: /bin/bash
    - stdout: True
    - unless: test -d /hana/shared/NDB/
    - require:
      - pkg: hana_required_packages
      - cmd: replace_components_dir_and_give_exec_permission

create_sapadmin_user:
  cmd.run:
    - name: |
        su - ndbadm -c 'hdbsql -u SYSTEM -p Passw0rd -n localhost:30013 -d NDB <<EOF
        CREATE USER SAPADMIN PASSWORD "Passw0rd" NO FORCE_FIRST_PASSWORD_CHANGE;
        ALTER USER SAPADMIN DISABLE PASSWORD LIFETIME;
        GRANT CONTENT_ADMIN TO SAPADMIN;
        GRANT AFLPM_CREATOR_ERASER_EXECUTE TO SAPADMIN;
        GRANT "IMPORT" TO SAPADMIN;
        GRANT "EXPORT" TO SAPADMIN;
        GRANT "INIFILE ADMIN" TO SAPADMIN;
        GRANT "LOG ADMIN" TO SAPADMIN;
        GRANT "CREATE SCHEMA","USER ADMIN","ROLE ADMIN","CATALOG READ" TO SAPADMIN WITH ADMIN OPTION;
        GRANT "CREATE ANY","SELECT" ON SCHEMA "SYSTEM" TO SAPADMIN WITH GRANT OPTION;
        GRANT "SELECT","EXECUTE","DELETE" ON SCHEMA "_SYS_REPO" TO SAPADMIN WITH GRANT OPTION;
        EOF'
    - stdout: True
    - unless: su - ndbadm -c "echo \"SELECT user_name FROM users WHERE user_name='SAPADMIN';\" | hdbsql -u SYSTEM -p Passw0rd -n localhost:30013 -d NDB" | awk '/^\"SAPADMIN\"$/ {print}' | tr -d '"' | grep -qx "SAPADMIN"

sap_prequisite:
  cmd.run:
    - name: |
        sap_dir=$(find / -type d -name "ServerComponents" 2>/dev/null | head -n 1)
        chmod +x -R "$sap_dir"
        sap_param_file=$(find / -type f -name "sap_param.cfg" 2>/dev/null | head -n 1)
        cp "$sap_param_file" /tmp/sap.cfg
        sed -i "s/serverfqdn/$(hostname)/g" /tmp/sap.cfg
    - shell: /bin/bash
    - stdout: True
    - user: root

sap_install:
  cmd.run:
    - name: |
        sap_dir=$(find / -type d -name "ServerComponents" 2>/dev/null | head -n 1)
        if [[ -d "$sap_dir" ]]; then
          cd "$sap_dir"
          echo "Installing SAP..."
          ./install -i silent -f /tmp/sap.cfg
        fi
    - cwd: /
    - user: root
    - shell: /bin/bash
    - stdout: True
    - require:
      - cmd: create_sapadmin_user
