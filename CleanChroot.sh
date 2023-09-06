#!/bin/bash
# shellcheck disable=
#
# Do some file cleanup...
#
#########################
CHROOT=${AMIGENCHROOT:-/mnt/ec2-root}
CLOUDCFG="$CHROOT/etc/cloud/cloud.cfg"
JRNLCNF="$CHROOT/etc/systemd/journald.conf"
KERNELSYSCFG="$CHROOT/etc/sysconfig/kernel"
#MAINTUSR=${MAINTUSR:-"maintuser"}
MAINTUSR=${MAINTUSR:-"ec2-user"}

# Disable EPEL repos
chroot "${CHROOT}" yum-config-manager --disable "*epel*" > /dev/null

# Remove SPEL and EPEL
chroot "${CHROOT}" yum erase -y spel-release
chroot "${CHROOT}" yum erase -y epel-release

# Get rid of stale RPM data
chroot "${CHROOT}" yum clean --enablerepo=* -y packages
chroot "${CHROOT}" rm -rf /var/cache/yum
chroot "${CHROOT}" rm -rf /var/lib/yum

# Nuke any history data
cat /dev/null > "${CHROOT}/root/.bash_history"

# Clean up all the log files
# shellcheck disable=SC2044
for FILE in $(find "${CHROOT}/var/log" -type f)
do
   cat /dev/null > "${FILE}"
done

# Enable persistent journal logging
if [[ $(grep -q ^Storage "${JRNLCNF}")$? -ne 0 ]]
then
   echo 'Storage=persistent' >> "${JRNLCNF}"
   install -d -m 0755 "${CHROOT}/var/log/journal"
   chroot "${CHROOT}" systemd-tmpfiles --create --prefix /var/log/journal
fi

# Help prevent longer-lived systems running out of space on /boot
sed -i '/^installonly_limit=/s/[0-9][0-9]*$/2/' "${CHROOT}/etc/yum.conf"

# Set TZ to UTC
rm "${CHROOT}/etc/localtime"
cp "${CHROOT}/usr/share/zoneinfo/UTC" "${CHROOT}/etc/localtime"

# Create maintuser
CLINITUSR=$(grep -E "name: (maintuser|centos|ec2-user|cloud-user)" \
            "${CLOUDCFG}" | awk '{print $2}')

if [ "${CLINITUSR}" = "" ]
then
   echo "Cannot reset value of cloud-init default-user" > /dev/stderr
else
   echo "Setting default cloud-init user to ${MAINTUSR}"
sed -i '/^system_info/,/^  ssh_svcname/d' "${CLOUDCFG}"
# shellcheck disable=SC1004
sed -i '/syntax=yaml/i\
system_info:\
  default_user:\
    name: '"${MAINTUSR}"'\
    lock_passwd: true\
    gecos: Local Maintenance User\
    groups: [wheel, adm, systemd-journal]\
    sudo: ["ALL=(ALL) NOPASSWD:ALL"]\
    shell: /bin/bash\
  distro: rhel\
  paths:\
    cloud_dir: /var/lib/cloud\
    templates_dir: /etc/cloud/templates\
  ssh_svcname: sshd\
' "${CLOUDCFG}"
fi

# Update NS-Switch map-file for SEL-enabled environment
printf "%-12s %s\n" sudoers: files >> "${CHROOT}/etc/nsswitch.conf"

# Ensure that /etc/sysconfig/kernel is present
echo "Populate /etc/sysconfig/kernel via heredoc"
cat << EOFKERNELSYSCFG > $KERNELSYSCFG
# UPDATEDEFAULT specifies if new-kernel-pkg should make
# new kernels the default
UPDATEDEFAULT=yes

# DEFAULTKERNEL specifies the default kernel package type
DEFAULTKERNEL=kernel
EOFKERNELSYSCFG