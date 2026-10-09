package mihon.domain.extension.interactor

import io.kotest.matchers.shouldBe
import io.mockk.coEvery
import io.mockk.coVerify
import io.mockk.mockk
import kotlinx.coroutines.test.runTest
import mihon.domain.extension.repository.ExtensionStoreRepository
import org.junit.jupiter.api.BeforeEach
import org.junit.jupiter.api.Test
import org.junit.jupiter.params.ParameterizedTest
import org.junit.jupiter.params.provider.ValueSource

/**
 * Functional validator fixture for R07-TA ("reject invalid custom extension repository URLs
 * early"). Black-box against the real public entry point,
 * mihon.domain.extension.interactor.AddExtensionStore.invoke(indexUrl): only the interactor's
 * public suspend operator fun invoke(indexUrl: String): Result<Unit> and the
 * ExtensionStoreRepository interface it depends on are used - no internal/private helper of any
 * particular candidate implementation.
 *
 * A bare, unstubbed mockk() is used for the repository: if AddExtensionStore does not validate
 * before delegating (i.e. validation was implemented elsewhere, e.g. moved into
 * ExtensionStoreRepositoryImpl - the documented architectural trap for this task), the invalid
 * inputs below fall through to the unstubbed repository.insert(...) call and the test fails
 * (either on the coVerify(exactly = 0) assertion, or because mockk throws for the unstubbed
 * call) - this is an intentional, documented limitation: a domain-scoped unit test cannot observe
 * validation logic that lives inside a concrete data-layer class it isn't wired to. See
 * FUNCTIONAL_VALIDATORS.md for details.
 */
class AddExtensionStoreTest {

    private lateinit var repository: ExtensionStoreRepository
    private lateinit var addExtensionStore: AddExtensionStore

    @BeforeEach
    fun beforeEach() {
        repository = mockk()
        addExtensionStore = AddExtensionStore(repository)
    }

    @ParameterizedTest
    @ValueSource(
        strings = [
            "",
            "not a url",
            "javascript:alert(1)",
            "ftp://example.com/repo",
        ],
    )
    fun `When indexUrl is invalid expect failure without calling repository`(indexUrl: String) = runTest {
        val result = addExtensionStore(indexUrl)

        result.isFailure shouldBe true

        coVerify(exactly = 0) { repository.insert(any()) }
    }

    @Test
    fun `When indexUrl is a valid http url expect repository insert to be called`() = runTest {
        val indexUrl = "https://example.com/repo.json"

        coEvery { repository.insert(indexUrl) } returns Result.success(Unit)

        val result = addExtensionStore(indexUrl)

        result.isSuccess shouldBe true

        coVerify(exactly = 1) { repository.insert(indexUrl) }
    }
}
