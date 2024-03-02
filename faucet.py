from web3 import Web3, HTTProvider


def impersonate_account(web3: Web3, address: str):
    """
    Impersonate account through Anvil without needing private key
    :param address:
        Account to impersonate
    """
    web3.provider.make_request("anvil_impersonateAccount", [address])


if __name__ == "__main__":
    PROVIDER = "http://127.0.0.1:8545"
  web3 = Web3(HTTPProvider(PROVIDER))
  impersonate_account(web3, "0x8aFf09e2259cacbF4Fc4e3E53F3bf799EfEEab36")
