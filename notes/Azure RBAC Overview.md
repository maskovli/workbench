# Azure Access Management Intro

- [Azure Access Management Intro](#azure-access-management-intro)
  - [Introduction](#introduction)
  - [Layer 1: MFA](#layer-1-mfa)
  - [Layer 2: Conditional Access](#layer-2-conditional-access)
  - [Layer 3: PAW](#layer-3-paw)
  - [Layer 4/5: Gates](#layer-45-gates)
    - [Layer 4, Gate 1: Access Packages](#layer-4-gate-1-access-packages)
    - [Layer 5, Gate 2: Privileged Identity Management](#layer-5-gate-2-privileged-identity-management)
  - [Tier Levels](#tier-levels)
  - [Role Assignment](#role-assignment)
    - [Azure AD Role Assignment](#azure-ad-role-assignment)
    - [Azure Management Group: VMP](#azure-management-group-vmp)
  - [Authentication Methods Explained (MFA)](#authentication-methods-explained-mfa)
  - [Portals of interest](#portals-of-interest)
  - [Support](#support)
    - [VMP IT](#vmp-it)
    - [Access Approvers](#access-approvers)
    - [Access Reviewers](#access-reviewers)
  - [Global Administrators](#global-administrators)

## Introduction

By following these guidelines, you will be able to access the resources you need while ensuring that our organization's security policies and compliance requirements are met. Please keep in mind that accessing privileged roles and resources requires an additional level of responsibility and diligence, so it's important to follow these guidelines carefully.

** Contact VMP IT with any questions, comments, or concerns.**

The following drawing illustrates the components used to govern, monitor, audit, and grant access to VMP Infrastructure environment, included but not limited to

- Microsoft 365
- Microsoft Azure and related services

![vmmarc](/.attachments/pictures/azure-am-rbac-01.png)

## Layer 1: MFA

MFA (Multi-Factor Authentication) is an extra layer of security that requires you to provide two or more pieces of evidence to prove your identity when logging in to an account. This can include something you know, like a password, and something you have, like a fingerprint or a security token.

## Layer 2: Conditional Access

Azure AD Conditional Access is a security feature that lets organizations control access to their resources based on specific conditions, such as user location, device type, or sign-in risk level. It helps ensure that only trusted users with authorized devices can access sensitive data and applications.

## Layer 3: PAW

A Privileged Access Workstation (PAW) is a specially secured computer that is used by VMP IT administrators to perform sensitive tasks, such as managing servers or accessing critical data. The PAW is isolated from the with security controls, and only authorized personnel can access it. This helps prevent unauthorized access and protects against cyber threats, such as malware or phishing attacks. By using a PAW, organizations can ensure that their IT administrators can work securely and effectively, without compromising the security of their systems and data.

## Layer 4/5: Gates

We use the term gates as these are "physical" barriers for just-in-time access (JIT).

### Layer 4, Gate 1: Access Packages

Azure AD Access packages are a way to manage access to resources in Azure AD more easily. Instead of assigning individual permissions to each user, we have created pre-defined packages of permissions that can be assigned to groups of users.

You have been assigned one or more access packages, depending on your qualified tier level at VMP and the resources you need to access. Each access package includes a set of permissions that have been pre-defined by our VMP IT, so you can be sure that you have the appropriate level of access to the resources you need to do your job.

When you need to access a resource that requires an access package, you can request access through the Azure portal (see the table below for the URL). Your request will be reviewed by our IT team, who will either approve or deny the request depending on your role and our organization's security policies.

Access packages function as a "first Gate, " ensuring you are appropriately entitled. You can access 1 or more packages based on your Tier level (1-4). The higher the number, the more privileges resulting in more demanding requirements for access.

Your access package will be monitored and reviewed frequently.

If you, for some reason, do not see your package, its no longer available to you, and you need to contact VMP IT.

### Layer 5, Gate 2: Privileged Identity Management

PIM is a feature in Azure AD that allows us to manage and control access to privileged roles and resources in our organization.

As you may know, privileged roles have access to sensitive data and critical systems, which makes them prime target for attackers. PIM allows us to control and monitor access to these roles by requiring users to request access and providing just-in-time access for a limited period.

You can request access through the PIM portal if you need to access a privileged role, group or resource. Your request will be reviewed by our IT team, who will either approve or deny the request depending on your role and our organization's security policies.

## Tier Levels

Tier levels are a way of categorizing the level of security required for different types of access. In access management, the higher the tier level, the more critical the key is to the organization, and the more security measures are required to protect it.

In general, higher tier levels require more rigorous security measures, such as stricter MFA and Conditional Access policies or more advanced authentication techniques, to ensure that only authorized users can access the organization's most sensitive information and systems.¨

The following matrix shows how VMP segmented the different tiers and thus their requirements.

![vmmarc](/.attachments/pictures/azure-am-rbac-vmp-05.png)

As you may notice, some features are in scope but not yet implemented. Privileged Access Workstation is for now on the drawing board but will surface as a hard requirement summer of 2023. Contact VMP IT for more information.

## Role Assignment

![vmmarc](/.attachments/pictures/azure-am-rbac-vmp-01.png)

### Azure AD Role Assignment

The following table illustrates the different roles in today's tier scope and what level it is assigned to. The total set of roles in Azure AD has not been assigned and is today pr. request. If you need additional roles added please get in touch with IT.

![vmmarc](/.attachments/pictures/azure-am-rbac-vmp-03.png)

### Azure Management Group: VMP

The following table illustrates the different IAM roles in Azure in today's tier scope and what level it is assigned to. The entire set of roles in Azure is not assigned and is today pr. request. If you need additional roles added, please get in touch with IT.

![vmmarc](/.attachments/pictures/azure-am-rbac-vmp-02.png)

## Authentication Methods Explained (MFA)

The following MFA methods are supported in the current environment for Privileged Access depending on the tier level you access. As a rule of thumb, the more privileged and entitled you are, the stronger the authentication methods have to be. Also, in some scenarios, there will be requirements for a Privileged Access Workstation (PAW)

- The Microsoft Authenticator app is a flagship authentication method, usable in passwordless approval modes. The app is free to download and use on Android/iOS mobile devices.
- FIDO2 security keys are a passwordless authentication method resistant to phishing attacks. This standard-based authentication method is available from multiple vendors.
- Certificate-based authentication is a passwordless authentication that is highly secure against phishing attacks. It uses x.509 certificates and an enterprise public key infrastructure (PKI) for authentication. With this method, there is no need for passwords, as the certificates act as the authentication factor.
- Temporary Access Pass, also known as TAP, is a passcode that has limited use or a time limit. It is designed to allow users to bootstrap new accounts, recover their accounts, or access their accounts when other authentication methods are unavailable. In essence, TAP is a backup authentication method that can help users access their accounts in exceptional circumstances. **Contact the service desk or VMP IT for TAP**

## Portals of interest

| Portal                     | Contacts                                                                                                         | URL                                                                                                |
| -------------------------- | ---------------------------------------------------------------------------------------------------------------- | -------------------------------------------------------------------------------------------------- |
| MyAccess                   | Access Packages                                                                                                  | https://myaccess.microsoft.com                                                                     |
| PIM Azure AD Roles         | Overview of all your eligible and active Azure AD Roles. Here you can activate a specific role.                  | https://entra.microsoft.com/#view/Microsoft_Azure_PIMCommon/ActivationMenuBlade/~/aadmigratedroles |
| PIM Groups                 | Overview of all your eligible and active Groups. These groups can lead to privileged access in M365 and/or Azure | https://entra.microsoft.com/#view/Microsoft_Azure_PIMCommon/ActivationMenuBlade/~/azurerbac        |
| PIM Azure Resources        | Overview all your eligible and active Azure resource roles.                                                      | https://entra.microsoft.com/#view/Microsoft_Azure_PIMCommon/ActivationMenuBlade/~/azurerbac        |
| MFA Setup                  | This portal will guide you through the process of setting up MFA for your accounts.                              | http://aka.ms/mfasetup                                                                             |
| Get back into your account | Portal for setting up Self-Service Password Reset (SSPR) in Microsoft accounts.team.                             | http://aka.ms/sspr                                                                                 |

## Support

These are the support channels you can use in order to get help if you for some reason are stuck and need help to get "unstuck":

### VMP IT

- Phone: +47 23971001
- Email: IT-Support@vinmonopolet.no
- Web: https://vmp.sharepoint.com/sites/IT-hjelp

### Access Approvers

The following personnel will deny/approve your access and titles:

|                           | Contacts                              |
| ------------------------- | ------------------------------------- |
| **First line approvers**  | Per-Ivar Bratbakken, Tobias Ødegaard, |
| **Second line approvers** | Bente Høydal                          |

### Access Reviewers

The following personnel will review your access and titles:
| | Contacts|
|--|--|
| **Access reviews** | Per-Ivar Bratbakken, Tobias Ødegaard |

## Global Administrators

The Global Administrator is the highest level of administrator role within Azure Active Directory (Azure AD), Microsoft's cloud-based identity and access management service. A Global Administrator has the ability to manage all aspects of the Azure AD tenant, including user and group management, domain management, application and service management, as well as security and compliance settings. Due to the level of access and control this role provides, it's crucial to safeguard it and ensure that it's used only when necessary.

Importance of safeguarding Global Administrator role:

- Security: Given the broad permissions granted to a Global Administrator, an attacker gaining access to this role could potentially compromise the entire Azure AD tenant, leading to unauthorized access to data, applications, and services.
- Compliance: Many organizations are subject to various regulatory requirements, which mandate strict control over privileged access. Safeguarding the Global Administrator role helps maintain compliance with these requirements.
- Minimizing human error: By limiting access to Global Administrator, you reduce the likelihood of unintentional changes that could negatively impact the organization.
- Privileged Access Management best practices: As a general best practice, the principle of least privilege should be applied to all users, granting them only the permissions necessary to perform their duties. This helps minimize the risk of unauthorized access and misuse.
  Reason for Break the Glass accounts:

A Break the Glass (BTG) account is a highly privileged emergency account designed to be used only in exceptional situations, such as when the regular Global Administrator accounts are unavailable or compromised. These accounts have strong, unique, and complex credentials that are stored securely offline. Some reasons for having BTG accounts are:

1. Emergency access: If all regular Global Administrator accounts become inaccessible (e.g., due to a security breach or accidental deletion), BTG accounts can be used to regain access and control.
2. Disaster recovery: In case of a major incident affecting the Azure AD tenant, BTG accounts provide a means to initiate disaster recovery procedures, allowing administrators to restore services and data.
3. Compartmentalization: By keeping BTG accounts separate from regular administrative accounts, organizations can minimize the risk of these highly privileged credentials being compromised in a security breach.

Overall, safeguarding the Global Administrator role and implementing Break the Glass accounts are essential for maintaining the security, compliance, and operational resilience of an organization's Azure AD environment.

![vmmarc](/.attachments/pictures/azure-am-rbac-vmp-04.png)
